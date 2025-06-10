function wt --description "Git worktree manager with advanced features"
    # Define help function
    function __wt_help
        echo "Git Worktree Manager - Manage Git worktrees efficiently"
        echo ""
        echo "Usage:"
        echo "  wt [options]                    - Interactive worktree selection with fzf"
        echo "  wt add <branch> [options]       - Create new branch and worktree"
        echo "  wt remove <branch> [options]    - Remove worktree and branch"
        echo "  wt list [options]               - List all worktrees"
        echo "  wt clean [options]              - Clean up stale worktrees"
        echo "  wt init                         - Create .wt_hook.fish template"
        echo "  wt main                         - Switch to default branch (main/master)"
        echo ""
        echo "Options:"
        echo "  -h, --help                      - Show this help message"
        echo "  -v, --verbose                   - Enable verbose output"
        echo "  -q, --quiet                     - Suppress informational output"
        echo ""
        echo "Add command options:"
        echo "  -b, --base <branch>             - Base branch (default: main)"
        echo "  --sync                          - Sync staged/modified/untracked files"
        echo "  --no-hook                       - Skip hook execution"
        echo ""
        echo "Clean command options:"
        echo "  -n, --dry-run                   - Show what would be removed"
        echo "  --days <n>                      - Remove worktrees older than n days"
        echo ""
        echo "Examples:"
        echo "  wt                              - Select worktree interactively"
        echo "  wt add feature/new-ui          - Create new feature branch"
        echo "  wt clean --days 30             - Remove worktrees older than 30 days"
        echo "  wt main                         - Switch to main branch"
    end

    # Parse global options - stop at first non-option argument
    argparse -s 'h/help' 'v/verbose' 'q/quiet' -- $argv
    or return 1

    # Handle help flag
    if set -ql _flag_help
        __wt_help
        return 0
    end

    # Set verbosity
    set -l verbose (set -ql _flag_verbose; and echo true; or echo false)
    set -l quiet (set -ql _flag_quiet; and echo true; or echo false)

    # Get subcommand
    set -l cmd $argv[1]
    set -e argv[1]

    # Main command logic
    switch "$cmd"
        case "" # Interactive selection
            __wt_interactive -- $verbose $quiet

        case add
            __wt_add -- $argv $verbose $quiet

        case remove rm
            __wt_remove -- $argv $verbose $quiet

        case list ls
            __wt_list -- $argv $verbose $quiet

        case clean
            __wt_clean -- $argv $verbose $quiet

        case init
            __wt_init -- $verbose $quiet

        case main default
            __wt_main -- $verbose $quiet

        case help
            __wt_help
            return 0

        case __preview
            # Internal preview command for fzf
            __wt_preview_worktree $argv
            return 0

        case '*'
            echo "Error: Unknown command '$cmd'" >&2
            echo "Run 'wt --help' for usage information." >&2
            return 1
    end
end

# Interactive worktree selection with fzf
function __wt_interactive
    # Parse arguments after --
    set -l verbose $argv[2]
    set -l quiet $argv[3]
    # Check if fzf is available
    if not command -sq fzf
        echo "Error: fzf is not installed. Please install fzf to use interactive mode." >&2
        return 1
    end

    # Get worktree list
    set -l worktrees (git worktree list 2>/dev/null)
    if test -z "$worktrees"
        echo "Error: No Git repository found or no worktrees exist." >&2
        return 1
    end

    # Extract branch names for fzf display
    set -l branch_names
    for worktree in $worktrees
        set -a branch_names (echo $worktree | string match -r '\[([^\]]+)\]' | string split -f2 '[' | string trim -c ']')
    end

    # Create a mapping of branch names to worktree info for preview
    set -l branch_worktree_map
    for i in (seq (count $branch_names))
        set branch_worktree_map[$i] $worktrees[$i]
    end
    
    # Select branch with fzf
    set -l selected_branch (printf '%s\n' $branch_names | fzf \
        --preview-window="right:70%:wrap" \
        --preview='
            set -l branch {}
            set -l line (git worktree list | grep "\[$branch\]")
            set -l worktree_path (echo $line | string split -f1 " ")
            set -l resolved_path (path resolve $worktree_path)
            
            echo "┌─ 🌳 Worktree Information ─────────────────────────┐"
            echo "│ Branch: $branch"
            echo "│ Path: $resolved_path"
            echo "└───────────────────────────────────────────────────┘"
            echo ""
            
            echo "📝 Changed Files:"
            echo (string repeat -n 50 "─")
            
            set -l changes (git -C "$resolved_path" status --porcelain 2>/dev/null)
            if test -z "$changes"
                echo "  ✨ Working tree clean"
            else
                set -l count 0
                for change in $changes
                    set count (math $count + 1)
                    if test $count -gt 10
                        echo "  ... and "(math (count $changes) - 10)" more files"
                        break
                    end
                    
                    set -l status (string sub -l 2 -- $change)
                    set -l file (string sub -s 4 -- $change)
                    
                    switch $status
                        case "M " " M" "MM"
                            echo "  🔧 Modified: $file"
                        case "A " "AM"
                            echo "  ➕ Added: $file"
                        case "D " " D"
                            echo "  ➖ Deleted: $file"
                        case "R "
                            echo "  ➡️  Renamed: $file"
                        case "??"
                            echo "  ❓ Untracked: $file"
                        case "*"
                            echo "  📄 $status $file"
                    end
                end
            end
            
            echo ""
            echo "📜 Recent Commits:"
            echo (string repeat -n 50 "─")
            git -C "$resolved_path" log --oneline --color=always -10 2>/dev/null | string replace -r "^" "  "
        ' \
        --header="🌲 Git Worktree Manager | ↵ Navigate | ^C Cancel" \
        --border=rounded \
        --height=80% \
        --layout=reverse \
        --prompt="🔍 Select branch: " \
        --ansi)
    
    if test -n "$selected_branch"
        # Find the worktree path for the selected branch
        set -l worktree_info (git worktree list | grep "\[$selected_branch\]")
        set -l worktree_path (echo $worktree_info | string split -f1 ' ')
        set -l resolved_path (path resolve $worktree_path)
        
        if test -d "$resolved_path"
            cd "$resolved_path"
            test "$verbose" = true; and echo "Switched to worktree: $resolved_path"
            return 0
        else
            echo "Error: Directory not found: $worktree_path" >&2
            return 1
        end
    end
end

# Preview function for fzf
function __wt_preview_worktree
    set -l line $argv[1]
    set -l worktree_path (echo $line | string split -f1 ' ')
    set -l branch (echo $line | string match -r '\[([^\]]+)\]' | string split -f2 '[' | string trim -c ']')
    
    # Resolve path
    set -l resolved_path (path resolve $worktree_path)
    
    echo "┌─ 🌳 Worktree Information ─────────────────────────┐"
    echo "│ Branch: $branch"
    echo "│ Path: $resolved_path"
    echo "└───────────────────────────────────────────────────┘"
    echo ""
    
    # Changed files
    echo "📝 Changed Files:"
    echo (string repeat -n 50 '─')
    
    set -l changes (git -C "$resolved_path" status --porcelain 2>/dev/null)
    if test -z "$changes"
        echo "  ✨ Working tree clean"
    else
        set -l count 0
        for change in $changes
            set count (math $count + 1)
            if test $count -gt 10
                echo "  ... and "(math (count $changes) - 10)" more files"
                break
            end
            
            set -l status (string sub -l 2 -- $change)
            set -l file (string sub -s 4 -- $change)
            
            switch $status
                case "M " " M" "MM"
                    echo "  🔧 Modified: $file"
                case "A " "AM"
                    echo "  ➕ Added: $file"
                case "D " " D"
                    echo "  ➖ Deleted: $file"
                case "R "
                    echo "  ➡️  Renamed: $file"
                case "??"
                    echo "  ❓ Untracked: $file"
                case '*'
                    echo "  📄 $status $file"
            end
        end
    end
    
    echo ""
    echo "📜 Recent Commits:"
    echo (string repeat -n 50 '─')
    git -C "$resolved_path" log --oneline --color=always -10 2>/dev/null | string replace -r '^' '  '
end

# Add new worktree
function __wt_add
    # The first argument is always "--", followed by actual arguments, then verbose and quiet
    set -l actual_argv $argv[2..-3]  # Skip first "--" and last two (verbose, quiet)
    set -l verbose $argv[-2]
    set -l quiet $argv[-1]
    
    # Parse add-specific options
    argparse 'b/base=' 'no-hook' 'sync' -- $actual_argv
    or return 1
    
    # Get branch name from remaining arguments after argparse
    set -l branch_name $argv[1]
    
    if test -z "$branch_name"
        echo "Error: Branch name required" >&2
        echo "Usage: wt add <branch_name> [options]" >&2
        return 1
    end
    
    # Store current directory and current branch before changing directory
    set -l original_dir $PWD
    set -l current_branch (git branch --show-current 2>/dev/null)
    
    # Always change to repository root for consistency
    set -l repo_root (git rev-parse --show-toplevel 2>/dev/null)
    if test -z "$repo_root"
        echo "Error: Not in a Git repository" >&2
        return 1
    end
    
    # Get the main git directory (handles both regular repos and worktrees)
    set -l git_common_dir (git rev-parse --git-common-dir 2>/dev/null)
    if test -z "$git_common_dir"
        echo "Error: Not in a Git repository" >&2
        return 1
    end
    
    # Resolve Git directory path
    set -l git_dir_resolved (path resolve $git_common_dir)
    
    cd "$repo_root"
    test "$verbose" = true; and echo "Changed to repository root: $repo_root"
    
    # Determine worktree directory
    # Create tmp_worktrees directory in .git
    set -l tmp_dir "$git_dir_resolved/tmp_worktrees"
    if not test -d "$tmp_dir"
        mkdir -p "$tmp_dir"
        test "$verbose" = true; and echo "Created directory: $tmp_dir"
    end
    
    # Generate timestamped directory name
    set -l timestamp (date +"%Y%m%d_%H%M%S")
    set -l dir_name "$timestamp"_"$branch_name"
    set -l worktree_path "$tmp_dir/$dir_name"
    
    # Get base branch (default to main)
    set -l base_branch
    if set -ql _flag_base
        set base_branch $_flag_base
    else if set -ql _flag_sync
        # If --sync flag is provided, use current branch as base
        set base_branch $current_branch
        test "$verbose" = true; and echo "Using current branch '$base_branch' as base (--sync flag provided)"
    else
        # Default to main branch
        set base_branch "main"
        # Check if main exists, otherwise try master
        if not git rev-parse --verify main &>/dev/null
            if git rev-parse --verify master &>/dev/null
                set base_branch "master"
            else
                # Fallback to current branch if neither main nor master exists
                set base_branch $current_branch
            end
        end
    end
    
    # Check for unstaged changes before creating worktree
    # Note: By default, we don't sync changes when base is main/master
    set -l should_sync_changes false
    set -l has_unstaged_changes (git status --porcelain 2>/dev/null)
    
    # Only sync changes if --sync flag is explicitly provided
    if set -ql _flag_sync
        set should_sync_changes true
        test "$verbose" = true; and echo "📝 Syncing changes (--sync flag provided)"
    else if test -n "$has_unstaged_changes"
        test "$verbose" = true; and echo "📝 Skipping unstaged changes sync (base: $base_branch, use --sync to include changes)"
    end
    
    # Create worktree
    test "$quiet" = false; and echo "Creating worktree for branch '$branch_name'..."
    
    if git worktree add -b "$branch_name" "$worktree_path" "$base_branch" &>/tmp/wt_add.log
        test "$quiet" = false; and echo "✅ Created worktree at: $worktree_path"
        test "$quiet" = false; and echo "📌 Branch: $branch_name (based on $base_branch)"
        
        # Store project root
        set -l project_root (git rev-parse --show-toplevel)
        
        # Sync all changes (staged, unstaged, and untracked) only if should_sync_changes is true
        if test "$should_sync_changes" = true
            test "$quiet" = false; and echo "🔄 Syncing all changes..."
            
            # Get list of files
            set -l staged_files (git diff --cached --name-only)
            set -l modified_files (git diff --name-only)
            set -l untracked_files (git ls-files --others --exclude-standard)
            
            # Copy staged files
            for file in $staged_files
                if test -f "$repo_root/$file"
                    set -l dir_path (dirname "$worktree_path/$file")
                    mkdir -p "$dir_path"
                    cp "$repo_root/$file" "$worktree_path/$file"
                    test "$verbose" = true; and echo "   📄 Copied staged: $file"
                end
            end
            
            # Copy modified files (unstaged changes)
            for file in $modified_files
                if test -f "$repo_root/$file"
                    set -l dir_path (dirname "$worktree_path/$file")
                    mkdir -p "$dir_path"
                    cp "$repo_root/$file" "$worktree_path/$file"
                    test "$verbose" = true; and echo "   📄 Copied modified: $file"
                end
            end
            
            # Copy untracked files
            for file in $untracked_files
                if test -f "$repo_root/$file"
                    set -l dir_path (dirname "$worktree_path/$file")
                    mkdir -p "$dir_path"
                    cp "$repo_root/$file" "$worktree_path/$file"
                    test "$verbose" = true; and echo "   📄 Copied untracked: $file"
                end
            end
            
            test "$quiet" = false; and echo "✅ Synced all changes"
        end
        
        # Change to new worktree
        cd "$worktree_path"
        
        # Execute hook if exists and not disabled
        if not set -ql _flag_no_hook; and test -f "$project_root/.wt_hook.fish"
            test "$quiet" = false; and echo "🎣 Executing .wt_hook.fish..."
            
            # Set environment variables for hook
            set -gx WT_WORKTREE_PATH "$worktree_path"
            set -gx WT_BRANCH_NAME "$branch_name"
            set -gx WT_BASE_BRANCH "$base_branch"
            set -gx WT_PROJECT_ROOT "$project_root"
            set -gx WT_TIMESTAMP (date +"%Y-%m-%d %H:%M:%S")
            
            source "$project_root/.wt_hook.fish"
            set -l hook_status $status
            
            # Clean up environment variables
            set -e WT_WORKTREE_PATH
            set -e WT_BRANCH_NAME
            set -e WT_BASE_BRANCH
            set -e WT_PROJECT_ROOT
            set -e WT_TIMESTAMP
            
            if test $hook_status -ne 0
                echo "⚠️  Hook execution failed with status $hook_status" >&2
            else
                test "$quiet" = false; and echo "✅ Hook executed successfully"
            end
        end
        
        test "$quiet" = false; and echo "🎯 Now in: $worktree_path"
    else
        echo "Error: Failed to create worktree" >&2
        test "$verbose" = true; and cat /tmp/wt_add.log >&2
        rm -f /tmp/wt_add.log
        return 1
    end
    
    rm -f /tmp/wt_add.log
end

# Remove worktree
function __wt_remove
    # The first argument is always "--", followed by actual arguments, then verbose and quiet
    set -l actual_argv $argv[2..-3]  # Skip first "--" and last two (verbose, quiet)
    set -l verbose $argv[-2]
    set -l quiet $argv[-1]
    
    set -l branch_name $actual_argv[1]
    
    # Get current branch
    set -l current_branch (git branch --show-current 2>/dev/null)
    
    # If no branch name provided, use fzf for interactive selection
    if test -z "$branch_name"
        # Check if fzf is available
        if not command -sq fzf
            echo "Error: Branch name required or install fzf for interactive selection" >&2
            echo "Usage: wt remove <branch_name>" >&2
            return 1
        end
        
        # Get worktree list excluding main/master and current branch
        set -l worktrees (git worktree list 2>/dev/null | grep -v '\[\(main\|master\)\]')
        if test -n "$current_branch"
            set worktrees (printf '%s\n' $worktrees | grep -v "\[$current_branch\]")
        end
        
        if test -z "$worktrees"
            echo "No removable worktrees found (main/master and current branches are protected)" >&2
            return 1
        end
        
        # Extract branch names for fzf display
        set -l branch_names
        for worktree in $worktrees
            set -a branch_names (echo $worktree | string match -r '\[([^\]]+)\]' | string split -f2 '[' | string trim -c ']')
        end
        
        # Select branch with fzf
        set -l selected_branch (printf '%s\n' $branch_names | fzf \
            --preview-window="right:70%:wrap" \
            --preview='
                set -l branch {}
                set -l line (git worktree list | grep "\[$branch\]")
                set -l worktree_path (echo $line | string split -f1 " ")
                set -l resolved_path (path resolve $worktree_path)
                
                echo "┌─ 🌳 Worktree Information ─────────────────────────┐"
                echo "│ Branch: $branch"
                echo "│ Path: $resolved_path"
                echo "└───────────────────────────────────────────────────┘"
                echo ""
                
                echo "📝 Changed Files:"
                echo (string repeat -n 50 "─")
                
                set -l changes (git -C "$resolved_path" status --porcelain 2>/dev/null)
                if test -z "$changes"
                    echo "  ✨ Working tree clean"
                else
                    set -l count 0
                    for change in $changes
                        set count (math $count + 1)
                        if test $count -gt 10
                            echo "  ... and "(math (count $changes) - 10)" more files"
                            break
                        end
                        
                        set -l status (string sub -l 2 -- $change)
                        set -l file (string sub -s 4 -- $change)
                        
                        switch $status
                            case "M " " M" "MM"
                                echo "  🔧 Modified: $file"
                            case "A " "AM"
                                echo "  ➕ Added: $file"
                            case "D " " D"
                                echo "  ➖ Deleted: $file"
                            case "R "
                                echo "  ➡️  Renamed: $file"
                            case "??"
                                echo "  ❓ Untracked: $file"
                            case "*"
                                echo "  📄 $status $file"
                        end
                    end
                end
                
                echo ""
                echo "📜 Recent Commits:"
                echo (string repeat -n 50 "─")
                git -C "$resolved_path" log --oneline --color=always -10 2>/dev/null | string replace -r "^" "  "
            ' \
            --header="🗑️ Select branch to remove | ↵ Select | ^C Cancel" \
            --border=rounded \
            --height=80% \
            --layout=reverse \
            --prompt="🔍 Remove branch: " \
            --ansi)
        
        if test -z "$selected_branch"
            echo "Cancelled"
            return 0
        end
        
        set branch_name $selected_branch
    end
    
    # Check if trying to remove current branch
    if test "$branch_name" = "$current_branch"
        echo "Error: Cannot remove the current branch '$branch_name'" >&2
        echo "Please switch to a different branch first." >&2
        return 1
    end
    
    # Check if trying to remove main/master branches
    if string match -qr '^(main|master)$' "$branch_name"
        echo "Error: Cannot remove protected branch '$branch_name'" >&2
        return 1
    end
    
    # Find worktree by branch
    set -l worktree_info (git worktree list | grep "\[$branch_name\]")
    
    if test -z "$worktree_info"
        echo "Error: No worktree found for branch '$branch_name'" >&2
        return 1
    end
    
    set -l worktree_path (echo $worktree_info | string split -f1 ' ')
    set -l resolved_path (path resolve $worktree_path)
    
    # Confirmation with default to yes
    echo "Remove worktree at: $resolved_path"
    echo "This will also delete branch: $branch_name"
    
    read -l -P "Are you sure? (Y/n) " confirm
    if string match -qi 'n' $confirm
        echo "Cancelled"
        return 0
    end
    
    # Remove worktree
    test "$quiet" = false; and echo "Removing worktree..."
    if git worktree remove --force "$worktree_path" &>/tmp/wt_remove.log
        test "$quiet" = false; and echo "✅ Removed worktree: $resolved_path"
        
        # Delete branch
        if git branch -D "$branch_name" &>>/tmp/wt_remove.log
            test "$quiet" = false; and echo "✅ Deleted branch: $branch_name"
        else
            echo "⚠️  Failed to delete branch: $branch_name" >&2
            test "$verbose" = true; and cat /tmp/wt_remove.log >&2
        end
    else
        echo "Error: Failed to remove worktree" >&2
        test "$verbose" = true; and cat /tmp/wt_remove.log >&2
        rm -f /tmp/wt_remove.log
        return 1
    end
    
    rm -f /tmp/wt_remove.log
end

# List worktrees
function __wt_list
    # The first argument is always "--", followed by actual arguments, then verbose and quiet
    set -l actual_argv $argv[2..-3]  # Skip first "--" and last two (verbose, quiet)
    set -l verbose $argv[-2]
    set -l quiet $argv[-1]
    
    # Get worktree list
    set -l worktrees (git worktree list 2>/dev/null)
    if test -z "$worktrees"
        echo "No worktrees found" >&2
        return 1
    end
    
    # Always show detailed format
    for worktree in $worktrees
        set -l path (echo $worktree | string split -f1 ' ')
        set -l branch (echo $worktree | string match -r '\[([^\]]+)\]' | string split -f2 '[' | string trim -c ']')
        set -l resolved (path resolve $path)
        
        # Get status
        set -l changes (git -C "$path" status --porcelain 2>/dev/null | count)
        set -l status_text (test $changes -eq 0; and echo "clean"; or echo "$changes changes")
        
        # Get last commit
        set -l last_commit (git -C "$path" log -1 --format="%h %s" 2>/dev/null)
        
        echo "Branch: $branch"
        echo "  Path: $resolved"
        echo "  Status: $status_text"
        echo "  Last commit: $last_commit"
        echo ""
    end
end

# Clean up stale worktrees
function __wt_clean
    # The first argument is always "--", followed by actual arguments, then verbose and quiet
    set -l actual_argv $argv[2..-3]  # Skip first "--" and last two (verbose, quiet)
    set -l verbose $argv[-2]
    set -l quiet $argv[-1]
    
    # Parse clean-specific options
    argparse 'n/dry-run' 'days=' -- $actual_argv
    or return 1
    
    set -l dry_run (set -ql _flag_dry_run; and echo true; or echo false)
    set -l days (set -ql _flag_days; and echo $_flag_days; or echo 30)
    
    # Validate days
    if not string match -qr '^\d+$' $days
        echo "Error: --days must be a positive number" >&2
        return 1
    end
    
    test "$quiet" = false; and echo "🧹 Cleaning worktrees older than $days days..."
    test "$dry_run" = true; and echo "🔍 DRY RUN - No changes will be made"
    echo ""
    
    set -l worktrees (git worktree list 2>/dev/null)
    if test -z "$worktrees"
        echo "No worktrees found" >&2
        return 1
    end
    
    set -l removed_count 0
    set -l cutoff_date (date -d "$days days ago" +%s 2>/dev/null; or date -v -"$days"d +%s)
    
    # Get current branch
    set -l current_branch (git branch --show-current 2>/dev/null)
    
    for worktree in $worktrees
        set -l path (echo $worktree | string split -f1 ' ')
        set -l branch (echo $worktree | string match -r '\[([^\]]+)\]' | string split -f2 '[' | string trim -c ']')
        
        # Skip main/master branches
        if string match -qr '^(main|master)$' $branch
            test "$verbose" = true; and echo "⏭️  Skipping protected branch: $branch"
            continue
        end
        
        # Skip current branch
        if test "$branch" = "$current_branch"
            test "$verbose" = true; and echo "⏭️  Skipping current branch: $branch"
            continue
        end
        
        # Check last modification time
        if test -d "$path"
            # Get last commit date
            set -l last_commit_date (git -C "$path" log -1 --format=%ct 2>/dev/null)
            if test -z "$last_commit_date"
                # If no commits, check directory modification time
                set -l dir_mtime (stat -f %m "$path" 2>/dev/null; or stat -c %Y "$path" 2>/dev/null)
                set last_commit_date $dir_mtime
            end
            
            if test -n "$last_commit_date" -a "$last_commit_date" -lt "$cutoff_date"
                set -l age_days (math "($cutoff_date - $last_commit_date) / 86400")
                echo "🗑️  Branch: $branch (inactive for $age_days days)"
                echo "   Path: $path"
                
                if test "$dry_run" = false
                    # Remove worktree
                    if git worktree remove --force "$path" &>/dev/null
                        # Remove branch
                        git branch -D "$branch" &>/dev/null
                        echo "   ✅ Removed"
                        set removed_count (math $removed_count + 1)
                    else
                        echo "   ❌ Failed to remove" >&2
                    end
                else
                    echo "   🔍 Would be removed"
                    set removed_count (math $removed_count + 1)
                end
                echo ""
            end
        else
            # Worktree directory doesn't exist
            echo "⚠️  Missing directory for branch: $branch"
            echo "   Path: $path"
            
            if test "$dry_run" = false
                if git worktree prune &>/dev/null
                    echo "   ✅ Pruned"
                    set removed_count (math $removed_count + 1)
                end
            else
                echo "   🔍 Would be pruned"
                set removed_count (math $removed_count + 1)
            end
            echo ""
        end
    end
    
    echo (string repeat -n 50 '─')
    if test "$dry_run" = true
        echo "Would remove $removed_count worktrees"
    else
        echo "Removed $removed_count worktrees"
    end
end

# Initialize hook template
function __wt_init
    # Parse arguments after --
    set -l verbose $argv[2]
    set -l quiet $argv[3]
    if test -f ".wt_hook.fish"
        echo "Error: .wt_hook.fish already exists" >&2
        echo "Remove it first if you want to recreate it." >&2
        return 1
    end
    
    echo '#!/usr/bin/env fish
# .wt_hook.fish - Executed after \'wt add\' command in worktree directory
#
# Available environment variables:
# - $WT_WORKTREE_PATH : Path to the new worktree (current directory)
# - $WT_BRANCH_NAME   : Name of the branch
# - $WT_BASE_BRANCH   : Base branch used for creation
# - $WT_PROJECT_ROOT  : Path to the original project root
# - $WT_TIMESTAMP     : Timestamp of worktree creation

# Example: Show creation info
echo "🎣 Worktree hook executing..."
echo "   Branch: $WT_BRANCH_NAME (from $WT_BASE_BRANCH)"
echo "   Location: $WT_WORKTREE_PATH"

# Files and directories to copy from project root
set -l copy_items \
    ".env" \
    ".env.local" \
    ".env.development" \
    ".claude" \
    "node_modules" \
    "vendor"

# Copy items if they exist
for item in $copy_items
    set -l source "$WT_PROJECT_ROOT/$item"
    set -l target "$WT_WORKTREE_PATH/$item"
    
    if test -e "$source"
        # Skip if target already exists
        if test -e "$target"
            echo "   ⏭️  Skipping $item (already exists)"
            continue
        end
        
        # Determine copy method based on type and name
        if test -d "$source"
            switch $item
                case "node_modules" "vendor" ".git"
                    # Create symlink for large directories
                    ln -s "$source" "$target"
                    echo "   🔗 Linked $item"
                case \'*\'
                    # Copy directory
                    cp -r "$source" "$target"
                    echo "   📁 Copied $item/"
            end
        else
            # Copy file
            cp "$source" "$target"
            echo "   📄 Copied $item"
        end
    end
end

# Example: Run initialization commands
# Uncomment and modify as needed:

# Install dependencies (if not linked)
# if not test -L "node_modules"
#     echo "📦 Installing dependencies..."
#     npm install
# end

# Run setup script
# if test -x "./scripts/setup.sh"
#     echo "🔧 Running setup script..."
#     ./scripts/setup.sh
# end

# Create branch-specific config
# echo "BRANCH=$WT_BRANCH_NAME" >> .env.local

echo "✅ Hook completed successfully"' > .wt_hook.fish
    
    chmod +x .wt_hook.fish
    
    test "$quiet" = false; and echo "✅ Created .wt_hook.fish template"
    test "$verbose" = true; and echo "Edit this file to customize worktree initialization"
    
    # Add to .gitignore if not already there
    if test -f .gitignore
        if not grep -q "^\.wt_hook\.fish\$" .gitignore
            echo ".wt_hook.fish" >> .gitignore
            test "$quiet" = false; and echo "📝 Added .wt_hook.fish to .gitignore"
        end
    end
end

# Switch to default branch (main/master)
function __wt_main
    # Parse arguments after --
    set -l verbose $argv[2]
    set -l quiet $argv[3]
    
    # Find default branch (main or master)
    set -l default_branch
    if git rev-parse --verify main &>/dev/null
        set default_branch "main"
    else if git rev-parse --verify master &>/dev/null
        set default_branch "master"
    else
        echo "Error: No default branch (main/master) found" >&2
        return 1
    end
    
    # Find worktree for default branch
    set -l worktree_info (git worktree list | grep "\[$default_branch\]")
    
    if test -z "$worktree_info"
        echo "Error: No worktree found for branch '$default_branch'" >&2
        echo "You may need to create it with: wt add $default_branch" >&2
        return 1
    end
    
    set -l worktree_path (echo $worktree_info | string split -f1 ' ')
    set -l resolved_path (path resolve $worktree_path)
    
    if test -d "$resolved_path"
        cd "$resolved_path"
        test "$quiet" = false; and echo "Switched to $default_branch branch"
        test "$verbose" = true; and echo "Path: $resolved_path"
        return 0
    else
        echo "Error: Directory not found: $resolved_path" >&2
        return 1
    end
end