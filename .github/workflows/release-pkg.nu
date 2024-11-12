#!/usr/bin/env nu

# Created: 2023/09/03 13:55:20
# Description:
#   A script to do the github release task, need nushell to be installed.

# The main binary file to be released
let os = $env.OS
let bin = 'crowbook'
let target = $env.TARGET
let src = $env.GITHUB_WORKSPACE
let flags = $env.TARGET_RUSTFLAGS
let dist = $'($env.GITHUB_WORKSPACE)/output'
let version = (open Cargo.toml | get package.version)

print $'Debugging info:'
print { version: $version, bin: $bin, os: $os, target: $target, src: $src, flags: $flags, dist: $dist }; hr-line -b

# $env

let USE_UBUNTU = 'ubuntu-22.04'

print $'(char nl)Packaging ($bin) v($version) for ($target) in ($src)...'; hr-line -b
if not ('Cargo.lock' | path exists) { cargo generate-lockfile }

print $'Start building ($bin)...'; hr-line

# ----------------------------------------------------------------------------
# Build for Ubuntu and macOS
# ----------------------------------------------------------------------------
if $os in [$USE_UBUNTU, 'macos-latest'] {
    if $os == $USE_UBUNTU {
        sudo apt-get install libxcb-composite0-dev pkg-config libssl-dev -y
    }
    if $target == 'aarch64-unknown-linux-gnu' {
        sudo apt-get install gcc-aarch64-linux-gnu -y
        $env.CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER = 'aarch64-linux-gnu-gcc'
        cargo-build-bin $flags
    } else if $target == 'armv7-unknown-linux-gnueabihf' {
        sudo apt-get install pkg-config gcc-arm-linux-gnueabihf -y
        $env.CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER = 'arm-linux-gnueabihf-gcc'
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
print $'Current executable file: ($executable)'

cd $src; mkdir $dist;
rm -rf $'target/($target)/release/*.d'
print $'(char nl)All executable files:'; hr-line
ls -f ($executable | into glob)

print $'(char nl)Copying release files...'; hr-line
cp -v README.md $'($dist)/README.md'
[LICENSE.md ($executable | into glob)] | each {|it| cp -rv $it $dist } | flatten

print $'(char nl)Check binary release version detail:'; hr-line
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
cd $dist; print $'(char nl)Creating release archive...'; hr-line
if $os in [$USE_UBUNTU, 'macos-latest'] {

    let files = (ls | get name)
    let dest = $'($bin)-($version)-($target)'
    let archive = $'($dist)/($dest).tar.gz'

    mkdir $dest
    $files | each {|it| mv $it $dest } | ignore

    print $'(char nl)(ansi g)Archive contents:(ansi reset)'; hr-line; ls $dest

    tar -czf $archive $dest
    print $'archive: ---> ($archive)'; ls $archive
    # REF: https://github.blog/changelog/2022-10-11-github-actions-deprecating-save-state-and-set-output-commands/
    echo $"archive=($archive)" | save --append $env.GITHUB_OUTPUT

} else if $os == 'windows-latest' {

    let releaseStem = $'($bin)-($version)-($target)'
    print $'(char nl)(ansi g)Archive contents:(ansi reset)'; hr-line; ls
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

# Create a line by repeating the unit with specified times
def build-line [
  times: int,
  unit: string = '-',
] {
  0..<$times | reduce -f '' { |i, acc| $unit + $acc }
}

# Print a horizontal line marker
export def hr-line [
  width?: int = 90,
  --blank-line(-b),
  --with-arrow(-a),
  --color(-c): string = 'g',
] {
  print $'(ansi $color)(build-line $width)(if $with_arrow {'>'})(ansi reset)'
  if $blank_line { print -n (char nl) }
}

# Get the specified env key's value or ''
def 'get-env' [
    key: string           # The key to get it's env value
    default: string = ''  # The default value for an empty env
] {
    $env | get -i $key | default $default
}
