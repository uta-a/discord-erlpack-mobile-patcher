package patcher

import (
	"crypto/sha256"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
)

const PatchMarker = "fake-mobile-status:erlpack-patcher:v1"

var officialWrappers = []string{
	"\"use strict\";\nmodule.exports = require('./discord_erlpack.node');",
	"\"use strict\";\nmodule.exports = require(\"./discord_erlpack.node\");",
}

type Channel string

const (
	Stable Channel = "stable"
	Canary Channel = "canary"
)

func (c Channel) DisplayName() string {
	if c == Canary {
		return "Discord Canary"
	}
	return "Discord Stable"
}

func (c Channel) InstallDirectory() string {
	if c == Canary {
		return "DiscordCanary"
	}
	return "Discord"
}

type Status string

const (
	Official Status = "official"
	Patched  Status = "patched"
	Unknown  Status = "unknown/third-party"
)

type Change string

const (
	Applied         Change = "patch applied"
	Restored        Change = "official wrapper restored"
	AlreadyApplied  Change = "patch is already applied"
	AlreadyOfficial Change = "wrapper is already official"
)

type Target struct {
	AppVersion string
	Wrapper    string
}

type versionCandidate struct {
	version   []uint64
	path      string
	appPrefix bool
}

func FindTarget(channelDirectory string) (Target, error) {
	appDirectories, err := versionDirectories(channelDirectory)
	if err != nil {
		return Target{}, fmt.Errorf("find Discord versions: %w", err)
	}
	for _, appDirectory := range appDirectories {
		erlpackDirectory, err := newestVersionDirectory(filepath.Join(appDirectory, "modules"), "discord_erlpack-")
		if err != nil {
			continue
		}
		wrapper := filepath.Join(erlpackDirectory, "discord_erlpack", "index.js")
		if info, err := os.Stat(wrapper); err == nil && !info.IsDir() {
			if err := ensureResolvedWithin(channelDirectory, wrapper); err != nil {
				return Target{}, err
			}
			return Target{AppVersion: filepath.Base(appDirectory), Wrapper: wrapper}, nil
		}
	}
	return Target{}, fmt.Errorf("discord_erlpack wrapper was not found under %s", channelDirectory)
}

func ensureResolvedWithin(base, target string) error {
	resolvedBase, err := filepath.EvalSymlinks(base)
	if err != nil {
		return fmt.Errorf("resolve Discord directory: %w", err)
	}
	resolvedTarget, err := filepath.EvalSymlinks(target)
	if err != nil {
		return fmt.Errorf("resolve discord_erlpack wrapper: %w", err)
	}
	relative, err := filepath.Rel(resolvedBase, resolvedTarget)
	if err != nil {
		return fmt.Errorf("compare resolved paths: %w", err)
	}
	if relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) || filepath.IsAbs(relative) {
		return fmt.Errorf("discord_erlpack wrapper resolves outside Discord directory: %s", resolvedTarget)
	}
	return nil
}

func Inspect(channelDirectory string) (Target, Status, error) {
	target, err := FindTarget(channelDirectory)
	if err != nil {
		return Target{}, "", err
	}
	content, err := os.ReadFile(target.Wrapper)
	if err != nil {
		return Target{}, "", fmt.Errorf("read wrapper: %w", err)
	}
	return target, classify(content), nil
}

func Install(channelDirectory, dataDirectory string, channel Channel) (Change, error) {
	target, status, err := Inspect(channelDirectory)
	if err != nil {
		return "", err
	}
	switch status {
	case Patched:
		return AlreadyApplied, nil
	case Unknown:
		return "", fmt.Errorf("refusing to overwrite unknown discord_erlpack wrapper: %s", target.Wrapper)
	}

	original, err := os.ReadFile(target.Wrapper)
	if err != nil {
		return "", fmt.Errorf("read official wrapper: %w", err)
	}
	backup := backupPath(dataDirectory, channel, target.AppVersion)
	if err := createVerifiedBackup(backup, original); err != nil {
		return "", err
	}
	if err := writeVerified(target.Wrapper, []byte(PatchedWrapper())); err != nil {
		return "", err
	}
	return Applied, nil
}

func Uninstall(channelDirectory, dataDirectory string, channel Channel) (Change, error) {
	target, status, err := Inspect(channelDirectory)
	if err != nil {
		return "", err
	}
	switch status {
	case Official:
		return AlreadyOfficial, nil
	case Unknown:
		return "", fmt.Errorf("patched wrapper has changed; refusing to overwrite it: %s", target.Wrapper)
	}

	backup := backupPath(dataDirectory, channel, target.AppVersion)
	original, err := os.ReadFile(backup)
	if err != nil {
		return "", fmt.Errorf("read official backup %s: %w", backup, err)
	}
	if classify(original) != Official {
		return "", errors.New("backup is not an official discord_erlpack wrapper")
	}
	if err := writeVerified(target.Wrapper, original); err != nil {
		return "", err
	}
	return Restored, nil
}

func PatchedWrapper() string {
	return `"use strict";
// ` + PatchMarker + `
const erlpack = require("./discord_erlpack.node");
const originalPack = erlpack.pack;

erlpack.pack = function (payload, ...rest) {
  let nextPayload = payload;
  try {
    if (payload?.op === 2 && payload?.d?.properties) {
      nextPayload = {
        ...payload,
        d: {
          ...payload.d,
          properties: {
            ...payload.d.properties,
            os: "Android",
            browser: "Discord Android",
            device: "Discord Android"
          }
        }
      };
    }
  } catch {
    nextPayload = payload;
  }
  return originalPack.call(this, nextPayload, ...rest);
};

module.exports = erlpack;
`
}

func classify(content []byte) Status {
	normalized := strings.TrimSpace(strings.ReplaceAll(string(content), "\r\n", "\n"))
	for _, official := range officialWrappers {
		if normalized == official {
			return Official
		}
	}
	if normalized == strings.TrimSpace(PatchedWrapper()) {
		return Patched
	}
	return Unknown
}

func createVerifiedBackup(path string, official []byte) error {
	if existing, err := os.ReadFile(path); err == nil {
		if classify(existing) != Official {
			return fmt.Errorf("existing backup is not official: %s", path)
		}
		return nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("read existing backup: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return fmt.Errorf("create backup directory: %w", err)
	}
	if err := writeVerified(path, official); err != nil {
		return fmt.Errorf("create backup: %w", err)
	}
	return nil
}

func writeVerified(path string, content []byte) error {
	info, err := os.Stat(path)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("inspect %s: %w", path, err)
	}
	mode := os.FileMode(0o600)
	if info != nil {
		mode = info.Mode().Perm()
	}

	temporary, err := os.CreateTemp(filepath.Dir(path), ".erlpack-patcher-*")
	if err != nil {
		return fmt.Errorf("create temporary file: %w", err)
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(mode); err != nil {
		temporary.Close()
		return fmt.Errorf("set temporary file permissions: %w", err)
	}
	if _, err := temporary.Write(content); err != nil {
		temporary.Close()
		return fmt.Errorf("write temporary file: %w", err)
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return fmt.Errorf("flush temporary file: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("close temporary file: %w", err)
	}
	if runtime.GOOS == "windows" {
		original, readErr := os.ReadFile(path)
		if readErr != nil && !errors.Is(readErr, os.ErrNotExist) {
			return fmt.Errorf("read existing file before replace: %w", readErr)
		}
		if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("remove existing file before replace: %w", err)
		}
		if err := os.Rename(temporaryPath, path); err != nil {
			if readErr == nil {
				_ = os.WriteFile(path, original, mode)
			}
			return fmt.Errorf("replace %s: %w", path, err)
		}
	} else if err := os.Rename(temporaryPath, path); err != nil {
		return fmt.Errorf("replace %s: %w", path, err)
	}
	actual, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("verify %s: %w", path, err)
	}
	if sha256.Sum256(actual) != sha256.Sum256(content) {
		return fmt.Errorf("write verification failed: %s", path)
	}
	return nil
}

func backupPath(dataDirectory string, channel Channel, appVersion string) string {
	return filepath.Join(dataDirectory, "backups", string(channel), appVersion, "discord_erlpack-index.js")
}

func newestVersionDirectory(base, prefix string) (string, error) {
	directories, err := prefixedVersionDirectories(base, prefix)
	if err != nil {
		return "", err
	}
	return directories[0], nil
}

func versionDirectories(base string) ([]string, error) {
	entries, err := os.ReadDir(base)
	if err != nil {
		return nil, err
	}
	var candidates []versionCandidate
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		version, ok := parseAppVersion(entry.Name())
		if ok {
			candidates = append(candidates, versionCandidate{
				version: version, path: filepath.Join(base, entry.Name()),
				appPrefix: strings.HasPrefix(entry.Name(), "app-"),
			})
		}
	}
	if len(candidates) == 0 {
		return nil, fmt.Errorf("no Discord app version directory found under %s", base)
	}
	return sortedCandidatePaths(candidates), nil
}

func prefixedVersionDirectories(base, prefix string) ([]string, error) {
	entries, err := os.ReadDir(base)
	if err != nil {
		return nil, err
	}
	var candidates []versionCandidate
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		version, ok := parseVersion(entry.Name(), prefix)
		if ok {
			candidates = append(candidates, versionCandidate{version: version, path: filepath.Join(base, entry.Name())})
		}
	}
	if len(candidates) == 0 {
		return nil, fmt.Errorf("no %s version directory found under %s", prefix, base)
	}
	return sortedCandidatePaths(candidates), nil
}

func sortedCandidatePaths(candidates []versionCandidate) []string {
	sort.Slice(candidates, func(i, j int) bool {
		comparison := compareVersions(candidates[i].version, candidates[j].version)
		if comparison == 0 {
			return candidates[i].appPrefix && !candidates[j].appPrefix
		}
		return comparison > 0
	})
	directories := make([]string, len(candidates))
	for index, candidate := range candidates {
		directories[index] = candidate.path
	}
	return directories
}

func parseAppVersion(name string) ([]uint64, bool) {
	if version, ok := parseVersion(name, "app-"); ok {
		return version, true
	}
	return parseVersion(name, "")
}

func parseVersion(name, prefix string) ([]uint64, bool) {
	value, ok := strings.CutPrefix(name, prefix)
	if !ok {
		return nil, false
	}
	parts := strings.Split(value, ".")
	version := make([]uint64, len(parts))
	for index, part := range parts {
		number, err := strconv.ParseUint(part, 10, 64)
		if err != nil {
			return nil, false
		}
		version[index] = number
	}
	return version, true
}

func compareVersions(left, right []uint64) int {
	length := max(len(left), len(right))
	for index := range length {
		var l, r uint64
		if index < len(left) {
			l = left[index]
		}
		if index < len(right) {
			r = right[index]
		}
		if l < r {
			return -1
		}
		if l > r {
			return 1
		}
	}
	return 0
}
