package main

import (
	"fmt"

	"github.com/uta-a/discord-erlpack-mobile-patcher/internal/patcher"
)

type installationCandidate struct {
	Channel   patcher.Channel
	Directory string
}

type installation struct {
	Channel    patcher.Channel
	Directory  string
	AppVersion string
	Status     patcher.Status
}

func discoverPlatformInstallations() ([]installation, error) {
	candidates, err := platformInstallationCandidates()
	if err != nil {
		return nil, err
	}
	return detectInstallations(candidates), nil
}

func detectInstallations(candidates []installationCandidate) []installation {
	installations := make([]installation, 0, len(candidates))
	for _, candidate := range candidates {
		target, status, err := patcher.Inspect(candidate.Directory)
		if err != nil {
			continue
		}
		installations = append(installations, installation{
			Channel:    candidate.Channel,
			Directory:  candidate.Directory,
			AppVersion: target.AppVersion,
			Status:     status,
		})
	}
	return installations
}

func selectAutomaticInstallation(installations []installation) (installation, error) {
	for _, channel := range []patcher.Channel{patcher.Stable, patcher.Canary} {
		selected, err := selectChannelInstallation(installations, channel)
		if err == nil {
			return selected, nil
		}
	}
	return installation{}, fmt.Errorf("no supported Discord installation was detected")
}

func selectChannelInstallation(installations []installation, channel patcher.Channel) (installation, error) {
	for _, candidate := range installations {
		if candidate.Channel == channel {
			return candidate, nil
		}
	}
	return installation{}, fmt.Errorf("%s was not detected", channel.DisplayName())
}

func printInstallations(installations []installation) error {
	if len(installations) == 0 {
		return fmt.Errorf("no supported Discord installation was detected")
	}
	fmt.Println("Detected Discord installations:")
	for _, detected := range installations {
		fmt.Printf("\n%s\n  Version: %s\n  Status:  %s\n  Path:    %s\n",
			detected.Channel.DisplayName(), detected.AppVersion, detected.Status, detected.Directory)
	}
	return nil
}
