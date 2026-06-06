package main

import (
	"errors"
	"fmt"

	"github.com/manifoldco/promptui"
	"github.com/uta-a/discord-erlpack-mobile-patcher/internal/patcher"
)

var errPromptInterrupted = errors.New("interactive prompt interrupted")

func runInteractive() error {
	fmt.Printf("Fake Mobile Status Installer %s\n\n", version)

	installations, err := discoverPlatformInstallations()
	if err != nil {
		return err
	}
	if len(installations) == 0 {
		return fmt.Errorf("no supported Discord installation was detected; use --discord-path for a custom location")
	}

	action, err := selectPrompt(
		"What would you like to do? (Press Enter to confirm)",
		[]string{"Install", "Uninstall", "View status", "Quit"},
	)
	if errors.Is(err, errPromptInterrupted) {
		return nil
	}
	if err != nil || action == "Quit" {
		return err
	}

	selected, err := promptInstallation(installations, action)
	if errors.Is(err, errPromptInterrupted) {
		return nil
	}
	if err != nil {
		return err
	}
	if action == "View status" {
		return executeInteractiveCommand("status", selected, "")
	}
	dataDirectory, err := platformDataDirectory()
	if err != nil {
		return err
	}
	if action == "Install" {
		return executeInteractiveCommand("install", selected, dataDirectory)
	}
	return executeInteractiveCommand("uninstall", selected, dataDirectory)
}

func executeInteractiveCommand(command string, selected installation, dataDirectory string) error {
	if err := executeCommand(command, selected, dataDirectory); err != nil {
		return fmt.Errorf("%s: %w", selected.Channel.DisplayName(), err)
	}
	return nil
}

func promptInstallation(installations []installation, action string) (installation, error) {
	items := make([]string, len(installations))
	for index, detected := range installations {
		items[index] = fmt.Sprintf("%s - %s [%s]",
			detected.Channel.DisplayName(), detected.AppVersion, installationStatusLabel(detected.Status))
	}
	_, selected, err := (&promptui.Select{
		Label: fmt.Sprintf("Select Discord installation to %s (Press Enter to confirm)", action),
		Items: items,
		Size:  len(items),
	}).Run()
	if err != nil {
		return installation{}, handlePromptError(err)
	}
	for index, item := range items {
		if item == selected {
			return installations[index], nil
		}
	}
	return installation{}, fmt.Errorf("selected Discord installation was not found")
}

func installationStatusLabel(status patcher.Status) string {
	switch status {
	case patcher.Official:
		return "NOT PATCHED"
	case patcher.Patched:
		return "PATCHED"
	default:
		return "UNKNOWN"
	}
}

func selectPrompt(label string, items []string) (string, error) {
	_, selected, err := (&promptui.Select{
		Label: label,
		Items: items,
		Size:  len(items),
	}).Run()
	if err != nil {
		return "", handlePromptError(err)
	}
	return selected, nil
}

func handlePromptError(err error) error {
	if errors.Is(err, promptui.ErrInterrupt) {
		return errPromptInterrupted
	}
	return fmt.Errorf("interactive prompt: %w", err)
}
