package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/uta-a/discord-erlpack-mobile-patcher/internal/patcher"
)

var version = "dev"
var interactiveMode bool

func main() {
	if err := run(); err != nil {
		writeResult(os.Stderr, false, err.Error())
		waitForInteractiveExit()
		os.Exit(1)
	}
	waitForInteractiveExit()
}

func run() error {
	channelFlag := flag.String("channel", "auto", "Discord channel: auto, stable, or canary")
	discordPath := flag.String("discord-path", "", "Override the Discord channel data directory")
	showVersion := flag.Bool("version", false, "Show version")
	flag.Usage = usage
	flag.Parse()

	if *showVersion {
		fmt.Printf("Fake Mobile Status Installer %s\n", version)
		return nil
	}

	if flag.NArg() == 0 {
		if *discordPath != "" || *channelFlag != "auto" {
			usage()
			return fmt.Errorf("a command is required when flags are specified")
		}
		interactiveMode = true
		return runInteractive()
	}
	if flag.NArg() != 1 {
		usage()
		return fmt.Errorf("exactly one command is required")
	}

	channel, automatic, err := parseChannel(*channelFlag)
	if err != nil {
		return err
	}
	if *discordPath != "" {
		if automatic {
			return fmt.Errorf("--discord-path requires --channel stable or --channel canary")
		}
		channelDirectory, dataDirectory, err := platformDirectories(channel, *discordPath)
		if err != nil {
			return err
		}
		return executeCommand(strings.ToLower(flag.Arg(0)), installation{
			Channel: channel, Directory: channelDirectory,
		}, dataDirectory)
	}

	installations, err := discoverPlatformInstallations()
	if err != nil {
		return err
	}
	command := strings.ToLower(flag.Arg(0))
	if automatic && command == "status" {
		return printInstallations(installations)
	}

	selected := installation{Channel: channel}
	if automatic {
		selected, err = selectAutomaticInstallation(installations)
	} else {
		selected, err = selectChannelInstallation(installations, channel)
	}
	if err != nil {
		return err
	}
	dataDirectory, err := platformDataDirectory()
	if err != nil {
		return err
	}
	return executeCommand(command, selected, dataDirectory)
}

func executeCommand(command string, selected installation, dataDirectory string) error {
	switch command {
	case "status":
		target, status, err := patcher.Inspect(selected.Directory)
		if err != nil {
			return err
		}
		fmt.Printf("%s\n  Version: %s\n  Status:  %s\n  Path:    %s\n",
			selected.Channel.DisplayName(), target.AppVersion, status, selected.Directory)
		return nil
	case "install":
		if err := ensureDiscordStopped(selected.Channel); err != nil {
			return err
		}
		change, err := patcher.Install(selected.Directory, dataDirectory, selected.Channel)
		if err != nil {
			return err
		}
		writeResult(os.Stdout, true, fmt.Sprintf("%s on %s", change, selected.Channel.DisplayName()))
		return nil
	case "uninstall":
		if err := ensureDiscordStopped(selected.Channel); err != nil {
			return err
		}
		change, err := patcher.Uninstall(selected.Directory, dataDirectory, selected.Channel)
		if err != nil {
			return err
		}
		writeResult(os.Stdout, true, fmt.Sprintf("%s on %s", change, selected.Channel.DisplayName()))
		return nil
	default:
		usage()
		return fmt.Errorf("unknown command %q", command)
	}
}

func platformDirectories(channel patcher.Channel, override string) (string, string, error) {
	if override != "" {
		absolute, err := filepath.Abs(override)
		if err != nil {
			return "", "", fmt.Errorf("resolve --discord-path: %w", err)
		}
		data, err := platformDataDirectory()
		return absolute, data, err
	}
	directories, err := platformInstallationCandidates()
	if err != nil {
		return "", "", err
	}
	for _, candidate := range directories {
		if candidate.Channel == channel {
			data, err := platformDataDirectory()
			return candidate.Directory, data, err
		}
	}
	return "", "", fmt.Errorf("%s directory is not configured", channel.DisplayName())
}

func platformInstallationCandidates() ([]installationCandidate, error) {
	switch runtime.GOOS {
	case "windows":
		localAppData := os.Getenv("LOCALAPPDATA")
		if localAppData == "" {
			return nil, fmt.Errorf("LOCALAPPDATA is not defined")
		}
		return []installationCandidate{
			{Channel: patcher.Stable, Directory: filepath.Join(localAppData, patcher.Stable.InstallDirectory())},
			{Channel: patcher.Canary, Directory: filepath.Join(localAppData, patcher.Canary.InstallDirectory())},
		}, nil
	case "darwin":
		home, err := os.UserHomeDir()
		if err != nil {
			return nil, fmt.Errorf("resolve home directory: %w", err)
		}
		support := filepath.Join(home, "Library", "Application Support")
		return []installationCandidate{
			{Channel: patcher.Stable, Directory: filepath.Join(support, "discord")},
			{Channel: patcher.Canary, Directory: filepath.Join(support, "discordcanary")},
		}, nil
	default:
		return nil, fmt.Errorf("unsupported operating system %q; use Windows or macOS", runtime.GOOS)
	}
}

func platformDataDirectory() (string, error) {
	switch runtime.GOOS {
	case "windows":
		localAppData := os.Getenv("LOCALAPPDATA")
		if localAppData == "" {
			return "", fmt.Errorf("LOCALAPPDATA is not defined")
		}
		return filepath.Join(localAppData, "FakeMobileStatus", "erlpack-patcher"), nil
	case "darwin":
		home, err := os.UserHomeDir()
		if err != nil {
			return "", fmt.Errorf("resolve home directory: %w", err)
		}
		return filepath.Join(home, "Library", "Application Support", "FakeMobileStatus", "erlpack-patcher"), nil
	default:
		return "", fmt.Errorf("unsupported operating system %q", runtime.GOOS)
	}
}

func parseChannel(value string) (patcher.Channel, bool, error) {
	switch strings.ToLower(value) {
	case "auto":
		return "", true, nil
	case "stable":
		return patcher.Stable, false, nil
	case "canary":
		return patcher.Canary, false, nil
	default:
		return "", false, fmt.Errorf("unknown channel %q; use auto, stable, or canary", value)
	}
}

func ensureDiscordStopped(channel patcher.Channel) error {
	if runtime.GOOS == "darwin" {
		processName := "Discord"
		if channel == patcher.Canary {
			processName = "Discord Canary"
		}
		err := exec.Command("pgrep", "-x", processName).Run()
		if err == nil {
			return fmt.Errorf("%s is running; fully quit it before changing the patch", channel.DisplayName())
		}
		var exitError *exec.ExitError
		if !errors.As(err, &exitError) || exitError.ExitCode() != 1 {
			return fmt.Errorf("inspect running processes: %w", err)
		}
		return nil
	}
	if runtime.GOOS != "windows" {
		return fmt.Errorf("unsupported operating system %q", runtime.GOOS)
	}
	image := "Discord.exe"
	if channel == patcher.Canary {
		image = "DiscordCanary.exe"
	}
	output, err := exec.Command("tasklist.exe", "/FI", "IMAGENAME eq "+image, "/FO", "CSV", "/NH").Output()
	if err != nil {
		return fmt.Errorf("inspect running processes: %w", err)
	}
	if strings.Contains(string(output), `"`+image+`"`) {
		return fmt.Errorf("%s is running; fully exit it before changing the patch", channel.DisplayName())
	}
	return nil
}

func usage() {
	fmt.Fprintln(flag.CommandLine.Output(), "Usage:")
	fmt.Fprintln(flag.CommandLine.Output(), "  erlpack-patcher")
	fmt.Fprintln(flag.CommandLine.Output(), "  erlpack-patcher [--channel auto|stable|canary] [--discord-path path] <status|install|uninstall>")
	flag.PrintDefaults()
}

func waitForInteractiveExit() {
	if !interactiveMode {
		return
	}
	fmt.Print("\nPress Enter to exit...")
	_, _ = fmt.Scanln()
}

func writeResult(output io.Writer, success bool, message string) {
	label := "Failed"
	if success {
		label = "Success"
	}
	fmt.Fprintf(output, "\n%s: %s\n", label, message)
}
