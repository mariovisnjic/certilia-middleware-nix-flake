# certilia-middleware-nix-flake

Nix flake for the [Certilia / AKD middleware](http://www.certilia.com/) — the
software stack for the Croatian eID card (osobna iskaznica): chip auth for
**e-Građani / NIAS** login and document signing.

Repackages the upstream Debian `.deb` from `repo.certilia.com` for NixOS:
patches the FHS interpreter, points the bundled Qt6 at its own libs/plugins,
and exposes the binaries + the PKCS#11 module.

It provides:

- **CertiliaClient** — GUI smart-card manager
- **CertiliaSigner** — localhost service browsers talk to for signing
- **libCertiliaPkcs11.so** — PKCS#11 module to load into Firefox/Chrome
  (exposed as `packages.default.pkcs11Module`)

> Not affiliated with Certilia/AKD. The middleware is proprietary.

> **Heads up:** pinned to a specific upstream version. A daily CI job opens a
> PR when Certilia ships a new release — once merged, run
> `nix flake update certilia-middleware` in your own flake to pick it up.

## Requirements

The middleware needs the PC/SC daemon and a compliant USB card reader:

```nix
services.pcscd.enable = true;
```

Only `x86_64-linux` is published upstream.

## Try it

```sh
nix run github:mariovisnjic/certilia-middleware-nix-flake#client
```

## Use as a flake input

```nix
{
  inputs.certilia-middleware.url = "github:mariovisnjic/certilia-middleware-nix-flake";
  inputs.certilia-middleware.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, certilia-middleware, ... }: {
    nixosConfigurations.<host> = nixpkgs.lib.nixosSystem {
      modules = [
        ({ pkgs, ... }: {
          services.pcscd.enable = true;
          environment.systemPackages = [
            certilia-middleware.packages.${pkgs.system}.default
          ];
        })
      ];
    };
  };
}
```

After rebuild, `CertiliaClient` / `CertiliaSigner` are on your PATH and the
desktop entries appear in your launcher.

### Browser PKCS#11 (e-Građani / NIAS)

For card-based web login, load the module into your browser's NSS DB.

Firefox via declarative policy:

```nix
programs.firefox.policies.SecurityDevices.Certilia =
  certilia-middleware.packages.${pkgs.system}.default.pkcs11Module;
```

Or manually: Firefox → *Settings → Privacy & Security → Security Devices →
Load*, and point it at the path printed by:

```sh
nix eval --raw github:mariovisnjic/certilia-middleware-nix-flake#default.pkcs11Module
```

### Signer autostart

`CertiliaSigner` must be running for in-browser signing. Start it from your
launcher, or autostart it (e.g. a systemd user service or
`exec-once = CertiliaSigner` under Hyprland).

## Bumping the version

A daily workflow (`.github/workflows/bump.yml`) updates `version` + `hash`
from the upstream Debian `Packages` index and opens a PR. To do it by hand:

1. Find the latest version + SHA256:
   ```sh
   curl -fsSL https://repo.certilia.com/repository/debian/dists/univ/main/binary-amd64/Packages \
     | grep -A8 '^Package: certiliamiddleware'
   ```
2. Set `version` in `flake.nix`.
3. Convert the SHA256 to SRI and replace `hash`:
   ```sh
   nix hash to-sri --type sha256 <sha256-hex>
   ```
