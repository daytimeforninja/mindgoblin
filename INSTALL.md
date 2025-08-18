# 🏠 Bringing Mind Goblin Home

Hello there! I'm so glad you're interested in trying Mind Goblin. You know, setting up new software can sometimes feel overwhelming, but I want you to know that this is going to be just fine. We'll take it one gentle step at a time.

## Ways to Welcome Mind Goblin

You have several wonderful ways to get started, and each one is perfectly valid. Choose whichever feels most comfortable to you.

### **Just Trying Things Out (No commitment needed!)**
```bash
# Take a peek and see what Mind Goblin can do:
nix run github:daytimeforninja/mindgoblin -- --help

# When you're ready, let's set up your special place:
nix run github:daytimeforninja/mindgoblin -- init

# And when you feel like it, try your first sync:
nix run github:daytimeforninja/mindgoblin -- sync
```

### **Making Mind Goblin Part of Your Daily Routine**
```bash
# If you'd like Mind Goblin to stay with you:
nix profile install github:daytimeforninja/mindgoblin

# Or if you prefer to build things yourself (that's wonderful too!):
git clone https://github.com/daytimeforninja/mindgoblin
cd mindgoblin
nix profile install .

# Now you can talk to Mind Goblin anytime:
mg --help
mg init
mg sync
```

### **Making Mind Goblin Part of Your System's Family**

If you're someone who likes to have everything organized and working together in your NixOS system, this approach might feel just right for you.

```nix
# In your flake.nix, you can invite Mind Goblin to join:
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    mind-goblin.url = "github:daytimeforninja/mindgoblin";
  };

  outputs = { self, nixpkgs, mind-goblin }: {
    nixosConfigurations.your-hostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        mind-goblin.nixosModules.default
      ];
    };
  };
}
```

```nix
# For your whole system:
{
  environment.systemPackages = [ 
    mind-goblin.packages.x86_64-linux.default 
  ];
}

# Or just for your home:
{
  home.packages = [
    inputs.mind-goblin.packages.${pkgs.system}.default
  ];
}

# And if you'd like Mind Goblin to help you automatically:
services.mind-goblin = {
  enable = true;
  user = "your-username";
  interval = "*:0/5";  # Every 5 minutes - gentle and unobtrusive
  todoFile = "/home/your-username/todo.txt";
};
```

## Setting Up Your Special Space

Now, let's create a comfortable place for Mind Goblin to help you. Don't worry if this seems like a lot - we'll go through each step together.

### **1. Creating your configuration home:**
```bash
mg init
```

This creates a special little folder where Mind Goblin keeps its settings. It's like giving it a cozy place to remember how you like things done.

### **2. Connecting to your calendar service:**
You'll want to open the file at `~/.config/mg/vdirsyncer.conf` and tell it about your calendar. Here's an example that you can change to fit your needs:

```ini
[storage mg_remote]
type = "caldav"
url = "https://caldav.fastmail.com/"      # This would be your calendar's address
username = "your-email@example.com"       # Your email or username
password.fetch = ["command", "pass", "caldav/fastmail"]  # A safe way to store your password
```

### **3. Making sure everything can talk to each other:**
```bash
vdirsyncer discover
```

This is like introducing Mind Goblin to your calendar service - they're going to be good friends!

### **4. Creating your first todo.txt file:**
```bash
echo "$(date +%Y-%m-%d)
• Buy groceries @errands
! Call dentist @urgent  
• Review project @work" > ~/todo.txt
```

Look at that! You've just created a beautiful, simple todo file. Each line starts with a special symbol that tells Mind Goblin what kind of task it is.

### **5. Your very first sync:**
```bash
mg sync
```

And just like that, your tasks are now living in both your simple text file and your calendar. Isn't that wonderful?

## If You Like to Tinker and Build Things

Sometimes it's nice to peek under the hood and see how things work, isn't it? If you're that kind of person, Mind Goblin welcomes you with open arms.

### **Setting up your workshop:**
```bash
nix develop

# Now you're in a special place where you can build and test:
cabal build
cabal test
cabal run mg -- --help
```

### **Building your very own copy:**
```bash
nix build
./result/bin/mg --help
```

## Your Daily Routine with Mind Goblin

Once everything is set up, using Mind Goblin becomes as natural as writing in your journal:

```bash
# A gentle sync whenever you're ready:
mg sync

# Sometimes you just want to send your tasks out:
mg push

# Other times you want to see what's been completed:
mg pull

# And isn't it nice to see how much you've accomplished?
mg stats

# If you ever need a reminder of what Mind Goblin can do:
mg --help
```

Your beautiful bullet journal entries will dance gracefully between your text file and any calendar you love, while keeping your `~/todo.txt` as clean and readable as the day you wrote it.

## When Mind Goblin Helps You Automatically

If you've chosen to let Mind Goblin help you automatically, it will work quietly in the background, just like a good neighbor should:

- Every few minutes, it gently checks if there's anything new to sync
- It runs as a thoughtful service that doesn't get in your way  
- If something unexpected happens, it handles it gracefully
- It keeps a quiet record of what it's doing, just in case you're curious

You can always check on how things are going:
```bash
systemctl --user status mind-goblin-sync.timer
systemctl --user status mind-goblin-sync.service
journalctl --user -u mind-goblin-sync.service
```

Remember, you're in control. Mind Goblin is just here to help make your life a little bit easier.