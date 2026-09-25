# Desired UTM VM and pinned Ubuntu installer. VM state lives in UTM, not Nix.
{
  name = "ubuntu-server-24.04";
  memoryMiB = 8192;
  cpuCores = 4;
  diskGiB = 128;
  iso = {
    url = "https://cdimage.ubuntu.com/ubuntu/releases/24.04/release/ubuntu-24.04.5-live-server-arm64.iso";
    sha256 = "f12484464c7d4d73e2167e0a7dbda1e669f8fae9bcf778dc0944937034b320cb";
  };
}
