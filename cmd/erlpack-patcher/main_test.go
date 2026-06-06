package main

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/uta-a/discord-erlpack-mobile-patcher/internal/patcher"
)

const testOfficialWrapper = "\"use strict\";\nmodule.exports = require('./discord_erlpack.node');\n"

func TestDetectInstallationsFindsStableAndCanaryWithStatus(t *testing.T) {
	stable := createTestInstallation(t, "stable", testOfficialWrapper)
	canary := createTestInstallation(t, "canary", patcher.PatchedWrapper())

	installations := detectInstallations([]installationCandidate{
		{Channel: patcher.Stable, Directory: stable},
		{Channel: patcher.Canary, Directory: canary},
	})

	if len(installations) != 2 {
		t.Fatalf("len(installations) = %d, want 2", len(installations))
	}
	if installations[0].Channel != patcher.Stable || installations[0].Status != patcher.Official {
		t.Fatalf("stable installation = %#v", installations[0])
	}
	if installations[1].Channel != patcher.Canary || installations[1].Status != patcher.Patched {
		t.Fatalf("canary installation = %#v", installations[1])
	}
}

func TestSelectAutomaticInstallationPrefersStable(t *testing.T) {
	installations := []installation{
		{Channel: patcher.Canary},
		{Channel: patcher.Stable},
	}

	selected, err := selectAutomaticInstallation(installations)
	if err != nil {
		t.Fatal(err)
	}
	if selected.Channel != patcher.Stable {
		t.Fatalf("channel = %q, want stable", selected.Channel)
	}
}

func TestSelectAutomaticInstallationFallsBackToCanary(t *testing.T) {
	selected, err := selectAutomaticInstallation([]installation{{Channel: patcher.Canary}})
	if err != nil {
		t.Fatal(err)
	}
	if selected.Channel != patcher.Canary {
		t.Fatalf("channel = %q, want canary", selected.Channel)
	}
}

func TestSelectAutomaticInstallationFailsWhenNothingWasDetected(t *testing.T) {
	if _, err := selectAutomaticInstallation(nil); err == nil {
		t.Fatal("selectAutomaticInstallation() error = nil, want error")
	}
}

func TestInstallationStatusLabel(t *testing.T) {
	tests := []struct {
		status patcher.Status
		want   string
	}{
		{status: patcher.Official, want: "NOT PATCHED"},
		{status: patcher.Patched, want: "PATCHED"},
		{status: patcher.Unknown, want: "UNKNOWN"},
	}
	for _, test := range tests {
		if got := installationStatusLabel(test.status); got != test.want {
			t.Errorf("installationStatusLabel(%q) = %q, want %q", test.status, got, test.want)
		}
	}
}

func TestWaitForInteractiveExitOnlyPromptsInInteractiveMode(t *testing.T) {
	previousMode := interactiveMode
	previousStdin := os.Stdin
	defer func() {
		interactiveMode = previousMode
		os.Stdin = previousStdin
	}()

	input, err := os.CreateTemp(t.TempDir(), "stdin")
	if err != nil {
		t.Fatal(err)
	}
	defer input.Close()
	if _, err := input.WriteString("\n"); err != nil {
		t.Fatal(err)
	}
	if _, err := input.Seek(0, 0); err != nil {
		t.Fatal(err)
	}
	os.Stdin = input

	interactiveMode = false
	waitForInteractiveExit()

	interactiveMode = true
	waitForInteractiveExit()
}

func TestResultLabelsAreExplicit(t *testing.T) {
	var output bytes.Buffer
	writeResult(&output, true, "patch applied on Discord Stable")
	writeResult(&output, false, "Discord Canary is running")

	got := output.String()
	if !bytes.Contains([]byte(got), []byte("Success: patch applied on Discord Stable")) {
		t.Fatalf("output does not contain success result: %q", got)
	}
	if !bytes.Contains([]byte(got), []byte("Failed: Discord Canary is running")) {
		t.Fatalf("output does not contain failure result: %q", got)
	}
}

func createTestInstallation(t *testing.T, name, content string) string {
	t.Helper()
	root := filepath.Join(t.TempDir(), name)
	wrapperDirectory := filepath.Join(
		root,
		"app-1.0.100",
		"modules",
		"discord_erlpack-1",
		"discord_erlpack",
	)
	if err := os.MkdirAll(wrapperDirectory, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(wrapperDirectory, "index.js"), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return root
}
