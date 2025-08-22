# Installation

## Quick Start

### Evaluation
```bash
nix run github:daytimeforninja/mindgoblin -- --help
nix run github:daytimeforninja/mindgoblin -- init
nix run github:daytimeforninja/mindgoblin -- sync
```

### Installation
```bash
# Via nix profile
nix profile install github:daytimeforninja/mindgoblin

# From source
git clone https://github.com/daytimeforninja/mindgoblin
cd mindgoblin
nix profile install .
```

## NixOS Integration

### Flake Input
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    mind-goblin.url = "github:daytimeforninja/mindgoblin";
  };

  outputs = { self, nixpkgs, mind-goblin }: {
    nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        mind-goblin.nixosModules.default
      ];
    };
  };
}
```

### System Package
```nix
# System-wide
environment.systemPackages = [ 
  mind-goblin.packages.x86_64-linux.default 
];

# User-specific (home-manager)
home.packages = [
  inputs.mind-goblin.packages.${pkgs.system}.default
];
```

### Systemd Service
```nix
services.mind-goblin = {
  enable = true;
  user = "username";
  interval = "*:0/5";  # Every 5 minutes
  todoFile = "/home/username/todo.txt";
};
```

## Configuration

### Initialize
```bash
mg init
```

### CalDAV Setup
Edit `~/.config/mg/vdirsyncer.conf`:

```ini
[storage mg_remote]
type = "caldav"
url = "https://caldav.example.com/"
username = "user@example.com"
password.fetch = ["command", "pass", "caldav/password"]
```

### Discovery
```bash
vdirsyncer discover
```

### First Todo File
```bash
cat > ~/todo.txt << EOF
$(date +%Y-%m-%d)
• Buy groceries @errands
! Call dentist @urgent  
• Review project @work
EOF
```

### First Sync
```bash
mg sync
```

## Development

### Development Shell
```bash
nix develop
cabal build
cabal test
cabal run mg -- --help
```

### Build
```bash
nix build
./result/bin/mg --help
```

## Usage

```bash
mg sync     # Bidirectional sync
mg push     # Upload to calendar
mg pull     # Download changes
mg stats    # Task statistics
mg --help   # Command reference
```

## Systemd Status

```bash
systemctl --user status mind-goblin-sync.timer
systemctl --user status mind-goblin-sync.service
journalctl --user -u mind-goblin-sync.service
```