package patcher

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const officialWrapper = "\"use strict\";\r\nmodule.exports = require('./discord_erlpack.node');\r\n"

func TestFindTargetSelectsNewestAppVersion(t *testing.T) {
	root := t.TempDir()
	createTarget(t, root, "app-1.0.99", officialWrapper)
	expected := createTarget(t, root, "app-1.0.100", officialWrapper)

	target, err := FindTarget(root)
	if err != nil {
		t.Fatal(err)
	}
	if target.Wrapper != expected {
		t.Fatalf("wrapper = %q, want %q", target.Wrapper, expected)
	}
}

func TestFindTargetSkipsIncompleteNewerAppVersion(t *testing.T) {
	root := t.TempDir()
	expected := createTarget(t, root, "app-1.0.100", officialWrapper)
	if err := os.MkdirAll(filepath.Join(root, "app-1.0.101", "modules"), 0o755); err != nil {
		t.Fatal(err)
	}

	target, err := FindTarget(root)
	if err != nil {
		t.Fatal(err)
	}
	if target.Wrapper != expected {
		t.Fatalf("wrapper = %q, want %q", target.Wrapper, expected)
	}
}

func TestFindTargetSupportsMacOSVersionDirectoryWithoutAppPrefix(t *testing.T) {
	root := t.TempDir()
	expected := createTarget(t, root, "0.0.1089", officialWrapper)

	target, err := FindTarget(root)
	if err != nil {
		t.Fatal(err)
	}
	if target.Wrapper != expected {
		t.Fatalf("wrapper = %q, want %q", target.Wrapper, expected)
	}
}

func TestFindTargetPrefersAppPrefixWhenSameVersionExists(t *testing.T) {
	root := t.TempDir()
	createTarget(t, root, "0.0.1089", officialWrapper)
	expected := createTarget(t, root, "app-0.0.1089", officialWrapper)

	target, err := FindTarget(root)
	if err != nil {
		t.Fatal(err)
	}
	if target.Wrapper != expected {
		t.Fatalf("wrapper = %q, want %q", target.Wrapper, expected)
	}
}

func TestPatchedWrapperHasNarrowFailOpenTransform(t *testing.T) {
	source := PatchedWrapper()
	required := []string{
		"payload?.op === 2 && payload?.d?.properties",
		"browser: \"Discord Android\"",
		"nextPayload = payload;",
		"return originalPack.call(this, nextPayload, ...rest);",
		PatchMarker,
	}
	for _, value := range required {
		if !strings.Contains(source, value) {
			t.Errorf("patch does not contain %q", value)
		}
	}
}

func TestInstallAndUninstallRoundTrip(t *testing.T) {
	root := t.TempDir()
	data := t.TempDir()
	wrapper := createTarget(t, root, "app-1.0.100", officialWrapper)

	if change, err := Install(root, data, Stable); err != nil || change != Applied {
		t.Fatalf("install = %v, %v", change, err)
	}
	assertFileContent(t, wrapper, PatchedWrapper())

	if change, err := Uninstall(root, data, Stable); err != nil || change != Restored {
		t.Fatalf("uninstall = %v, %v", change, err)
	}
	assertFileContent(t, wrapper, officialWrapper)
}

func TestInstallRefusesUnknownWrapper(t *testing.T) {
	root := t.TempDir()
	data := t.TempDir()
	wrapper := createTarget(t, root, "app-1.0.100", "module.exports = thirdParty;\n")

	_, err := Install(root, data, Stable)
	if err == nil || !strings.Contains(err.Error(), "unknown") {
		t.Fatalf("error = %v, want unknown wrapper error", err)
	}
	assertFileContent(t, wrapper, "module.exports = thirdParty;\n")
}

func TestUninstallRefusesChangedPatch(t *testing.T) {
	root := t.TempDir()
	data := t.TempDir()
	wrapper := createTarget(t, root, "app-1.0.100", officialWrapper)
	if _, err := Install(root, data, Stable); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(wrapper, []byte(PatchedWrapper()+"// changed\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	_, err := Uninstall(root, data, Stable)
	if err == nil || !strings.Contains(err.Error(), "changed") {
		t.Fatalf("error = %v, want changed patch error", err)
	}
}

func TestResolvedTargetMustRemainInsideDiscordDirectory(t *testing.T) {
	base := t.TempDir()
	outside := filepath.Join(t.TempDir(), "index.js")
	if err := os.WriteFile(outside, []byte(officialWrapper), 0o644); err != nil {
		t.Fatal(err)
	}

	err := ensureResolvedWithin(base, outside)
	if err == nil || !strings.Contains(err.Error(), "outside Discord directory") {
		t.Fatalf("error = %v, want outside directory error", err)
	}
}

func createTarget(t *testing.T, root, appVersion, content string) string {
	t.Helper()
	directory := filepath.Join(
		root,
		appVersion,
		"modules",
		"discord_erlpack-1",
		"discord_erlpack",
	)
	if err := os.MkdirAll(directory, 0o755); err != nil {
		t.Fatal(err)
	}
	wrapper := filepath.Join(directory, "index.js")
	if err := os.WriteFile(wrapper, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return wrapper
}

func assertFileContent(t *testing.T, path, expected string) {
	t.Helper()
	actual, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(actual) != expected {
		t.Fatalf("content = %q, want %q", actual, expected)
	}
}
