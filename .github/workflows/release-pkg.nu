#!/usr/bin/env nu

# Created: 2022/12/09 13:55:20
# Description:
#   A script to do the github release task, need nushell to be installed.
# REF:
#   1. https://github.com/volks73/cargo-wix

# The main binary file to be released
let os = $env.OS
let bin = 'crowbook'
let target = $env.TARGET
let src = $env.GITHUB_WORKSPACE
let flags = $env.TARGET_RUSTFLAGS
let dist = $'($env.GITHUB_WORKSPACE)/output'
let version = (open Cargo.toml | get package.version)

$'Debugging info:'
print { version: $version, bin: $bin, os: $os, target: $target, src: $src, flags: $flags, dist: $dist }; hr-line -b

# $env

let USE_UBUNTU = 'ubuntu-20.04'

$'(char nl)Packaging ($bin) v($version) for ($target) in ($src)...'; hr-line -b
if not ('Cargo.lock' | path exists) { cargo generate-lockfile }

$'Start building ($bin)...'; hr-line

# ----------------------------------------------------------------------------
# Build for Ubuntu and macOS
# ----------------------------------------------------------------------------
if $os in [$USE_UBUNTU, 'macos-latest'] {
    if $os == $USE_UBUNTU {
        sudo apt-get install libxcb-composite0-dev pkg-config libssl-dev -y
    }
    if $target == 'aarch64-unknown-linux-gnu' {
        sudo apt-get install gcc-aarch64-linux-gnu -y
        let-env CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER = 'aarch64-linux-gnu-gcc'
        cargo-build-bin $flags
    } else if $target == 'armv7-unknown-linux-gnueabihf' {
        sudo apt-get install pkg-config gcc-arm-linux-gnueabihf -y
        let-env CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER = 'arm-linux-gnueabihf-gcc'
        cargo-build-bin $flags
    } else {
        # musl-tools to fix 'Failed to find tool. Is `musl-gcc` installed?'
        # Actually just for x86_64-unknown-linux-musl target
        if $os == $USE_UBUNTU { sudo apt install musl-tools -y }
        cargo-build-bin $flags
    }
}

# ----------------------------------------------------------------------------
# Build for Windows
# ----------------------------------------------------------------------------
if $os in ['windows-latest'] {
    if ($flags | str trim | is-empty) {
        cargo build --release --all --target $target
    } else {
        cargo build --release --all --target $target $flags
    }
}

# ----------------------------------------------------------------------------
# Prepare for the release archive
# ----------------------------------------------------------------------------
let suffix = if $os == 'windows-latest' { '.exe' }
let executable = $'target/($target)/release/($bin)*($suffix)'
$'Current executable file: ($executable)'

cd $src; mkdir $dist;
rm -rf $'target/($target)/release/*.d'
$'(char nl)All executable files:'; hr-line
ls -f $executable

$'(char nl)Copying release files...'; hr-line
cp -v README.md $'($dist)/README.md'
[LICENSE.md $executable] | each {|it| cp -rv $it $dist } | flatten

$'(char nl)Check binary release version detail:'; hr-line
let ver = if $os == 'windows-latest' {
    (do -i { ./output/crowbook.exe --version }) | str join
} else {
    (do -i { ./output/crowbook --version }) | str join
}
if ($ver | str trim | is-empty) {
    $'(ansi r)Incompatible release binary...(ansi reset)'
} else { $ver }

# ----------------------------------------------------------------------------
# Create a release archive and send it to output for the following steps
# ----------------------------------------------------------------------------
cd $dist; $'(char nl)Creating release archive...'; hr-line
if $os in [$USE_UBUNTU, 'macos-latest'] {

    let files = (ls | get name)
    let dest = $'($bin)-($version)-($target)'
    let archive = $'($dist)/($dest).tar.gz'

    mkdir $dest
    $files | each {|it| mv $it $dest } | ignore

    $'(char nl)(ansi g)Archive contents:(ansi reset)'; hr-line; ls $dest

    tar -czf $archive $dest
    print $'archive: ---> ($archive)'; ls $archive
    # REF: https://github.blog/changelog/2022-10-11-github-actions-deprecating-save-state-and-set-output-commands/
    echo $"archive=($archive)" | save --append $env.GITHUB_OUTPUT

} else if $os == 'windows-latest' {

    let releaseStem = $'($bin)-($version)-($target)'
    $'(char nl)(ansi g)Archive contents:(ansi reset)'; hr-line; ls
    let archive = $'($dist)/($releaseStem).zip'
    7z a $archive *
    print $'archive: ---> ($archive)';
    let pkg = (ls -f $archive | get name)
    if not ($pkg | is-empty) {
        echo $"archive=($pkg | get 0)" | save --append $env.GITHUB_OUTPUT
    }
}

def 'cargo-build-bin' [ options: string ] {
    if ($options | str trim | is-empty) {
        cargo build --release --all --target $target
    } else {
        cargo build --release --all --target $target $options
    }
}

# Print a horizontal line marker
def 'hr-line' [
    --blank-line(-b): bool
] {
    print $'(ansi g)---------------------------------------------------------------------------->(ansi reset)'
    if $blank_line { char nl }
}

# Get the specified env key's value or ''
def 'get-env' [
    key: string           # The key to get it's env value
    default: string = ''  # The default value for an empty env
] {
    $env | get -i $key | default $default
}
