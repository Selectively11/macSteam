# macsteam 

"Steam unlock client" for macOS. ARM macOS, specifically. **This does not support Intel Macs!**

## Huh?

If you don't know what a Steam Unlock Client is, think 'SteamTools/OpenSteamTool/HubcapTools'. SLSSteam if you have good taste. If you don't know what those are, this isn't for you.

This is a minimal unlock client, at the moment. It supports game ownership spoofing ('unlocking') and license injection/downloading. It also has an achievement schema fetcher that is, umm, heavily 'inspired' by the one used in [SLSSteam](https://github.com/AceSLS/SLSsteam) but is no where as good or as well tested as that component was re-engineered hastily over the course of a few hours so that I could release.... 

Other than that one thing, this is an original work. It is _not_ a port of OpenSteamTool or SLSSteam to macOS. 

Manifests for injected games are fetched from the OpenSteamTool endpoint, as needed. I didn't want to build my own manifest delivery endpoint, theirs has been reliable [EDIT: this aged well!] so it is used. Open source stuff and all that.

## How?

1. The config app deploys a dylib 'into' the Steam app bundle. 
2. A dylib (`macsteam.dylib`) is injected into Steam on launch, which does the unlock work.

Pretty boring. 

## macSteam Config

The companion app can handle all the basics. It can deploy the macSteam dylib, it can import games, you can use it to remove games from your unlock list, you can toggle the features that support being toggled (with more to come). You can also edit the config by hand by going to ```~/Library/Application Support/macSteam``` and editing the config file.

## Usage

Download the latest release from the [Releases page](https://github.com/Selectively11/macsteam/releases).

Unzip it. Move macSteam Config to Applications. 

Go to Install, hit Install, let macSteam deploy. You will get a TCC prompt to allow macSteam to modify other applications, allow it.

## Building from source

The dylib:

```bash
make rebuild
```

The config app:

```bash
cd macsteam-app
swift package resolve
swift test
bash make_app.sh
```

There is also a science experiment in the repo, a macSteam launcher that does not modify the Steam app bundle in any way. It is included for the enjoyment of others, but is not intended to be used. 

## Contributing

PRs are welcome. I could currently badly use a **real name** and an **icon**. I'll be implementing more features in the coming days/weeks. I'll add proper Family Share stuff shortly with other features coming based on demand. Once the core feature set is solid, I'll bring [CloudRedirect](https://github.com/Selectively11/CloudRedirect) into the project.

## License

macSteam is distributed under the GNU Affero General Public License version 3.
See [LICENSE](LICENSE). Third-party attribution is recorded in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
