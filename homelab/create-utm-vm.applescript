-- Called by configure-homelab.sh as the logged-in user. UTM's scripting API
-- creates the VM bundle and its sparse disk in UTM's normal library.
on run args
    set vmName to item 1 of args
    set isoPath to item 2 of args
    set ramMiB to (item 3 of args) as integer
    set cores to (item 4 of args) as integer
    set diskMiB to (item 5 of args) as integer
    set operation to item 6 of args
    if operation is "create" then set installerIso to POSIX file isoPath

    tell application "UTM"
        repeat with candidate in virtual machines
            if name of candidate is vmName then
                set existingConfig to configuration of candidate
                if backend of candidate is not apple then error "Existing VM uses a different UTM backend: " & vmName
                if memory of existingConfig is not ramMiB then error "Existing VM has a different RAM size: " & vmName
                if cpu cores of existingConfig is not cores then error "Existing VM has a different CPU count: " & vmName
                set fixedDiskId to missing value
                repeat with driveConfig in drives of existingConfig
                    if removable of driveConfig is false then set fixedDiskId to id of driveConfig
                end repeat
                if fixedDiskId is missing value then error "Existing VM has no fixed disk: " & vmName
                return "existing:" & fixedDiskId
            end if
        end repeat

        if operation is "check" then return "missing"
        set newVm to make new virtual machine with properties {backend:apple, configuration:{name:vmName, memory:ramMiB, cpu cores:cores, drives:{{removable:true, source:installerIso}, {guest size:diskMiB}}, network interfaces:{{mode:shared}}, displays:{{dynamic resolution:false}}}}
        return "Created UTM VM: " & name of newVm
    end tell
end run
