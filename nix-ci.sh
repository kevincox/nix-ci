#! /bin/bash

set -ex

if [ -n "$SECRETS_URL" ]; then
	echo "# FETCHING SECRETS"
	wget -O secrets.archive "$SECRETS_URL"
	if [ -n "$SECRETS_KEY" ]; then
		gpg --d --passphrase-fd <(echo "$SECRETS_KEY") -o secrets.archive secrets.archive
	fi
	tar -xf secrets.archive
fi

if [ -z "$DEPLOY" ]; then
	flags=()
else
	flags=(-j2)
fi

if [ '!' -d /nix ]; then
	echo "# INSTALLING NIX"
	curl -fsS https://nixos.org/nix/install | bash
	source ~/.nix-profile/etc/profile.d/nix.sh
fi

sudo install -Dm644 secrets/nix.conf /etc/nix.conf

nix-build "${flags[@]}" -A ${BUILD_ATTR:-all}

if [ -n "$DEPLOY" -a -f secrets/b2-bucket ]; then
	nix-env -i /nix/store/515ldhb5mkwgw939x9ml61bbklibpk81-b2-nix-cache
	nix-env -iA nixpkgs.backblaze-b2
	backblaze-b2 authorize_account $(cat secrets/b2-cred)
	b2-nix-cache $(cat secrets/b2-bucket) secrets/nix-cache-key
fi
