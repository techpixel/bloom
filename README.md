# Bloom

Bloom notices the time you spend with friends in person, asks how it felt, and shows you the story of your friendships across the week and the month. This repo is a working SwiftUI prototype for iPhone and Mac.

## Run it

Open `SVSD.xcodeproj` in Xcode 16 or later and run the `SVSD` scheme on an iPhone simulator, your own iPhone, or **My Mac (Mac Catalyst)**. There are no third-party dependencies.

To run it on your own iPhone, select the project, open **Signing & Capabilities**, pick your team, and change the bundle identifier to one of your own.

Debug builds include developer tools: a menu (wrench) for jumping to any screen, a pin for leaving design feedback, and a Replay button on the welcome screen. Release builds leave them out.

## The judge's demo

`scripts/build-judge-mac.sh` builds a Mac version for reviewers and zips it into `dist/Bloom-demo.zip`. It uses two made-up friends instead of real people and opens with a short note explaining what's simulated.

## What's simulated

Phone verification, the permission prompts, contacts, location, calendars and the hangout log are all simulated. The app doesn't read your contacts, track your location or access your calendar, except when you choose your own contact card for a profile photo or text a friend from your contacts.

## Photo credits

Place photos come from Wikimedia Commons under CC0, public-domain, CC BY and CC BY-SA licences. See [PHOTO-CREDITS.md](PHOTO-CREDITS.md) for each photo's author and licence.
