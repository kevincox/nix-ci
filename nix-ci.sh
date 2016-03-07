#! /bin/bash

set -ex

if [ -n "$SECRETS_URL" ]; then
	echo "# FETCHING SECRETS"
	wget -O secrets.archive "$SECRETS_URL"
	if [ -n "$SECRETS_KEY" ]; then
		gpg -d --batch --passphrase-file <(echo "$SECRETS_KEY") -o secrets.archive-decrypted secrets.archive
		mv secrets.archive-decrypted secrets.archive
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

[ -f secrets/nix.conf ] && sudo install -Dm644 secrets/nix.conf /etc/nix/nix.conf

nix-build "${flags[@]}" -A ${BUILD_ATTR:-all}

if [ -n "$DEPLOY" -a -f secrets/b2-bucket ]; then
	nix-env -i /nix/store/zqjdi3frwj2372w7xfwibj3dwak08x32-b2-nix-cache
	nix-env -iA nixpkgs.backblaze-b2
	backblaze-b2 authorize_account $(cat secrets/b2-cred)
	b2-nix-cache $(cat secrets/b2-bucket) secrets/nix-cache-key
fi

if [ -n "$DEPLOY" -a -f result-marathon ]; then
	cat result-marathon
	args=(
		-isS
		-X PUT
		'-HContent-Type: application/json'
		--data-binary @result-marathon
		"$(cat secrets/marathon)/v2/apps"
	)
	[ -f secrets/marathon.ca.crt ] && args+=(--cacert secrets/marathon.ca.crt)
	[ -f secrets/marathon.crt ]    && args+=(--cert secrets/marathon.crt)
	[ -f secrets/marathon.key ]    && args+=(--key secrets/marathon.key)
	
	# Make request.
	r=$(curl "${args[@]}")
	# Print response.
	echo "$r"
	# Fail unless status is 200
	head -n1 <<<"$r" | grep -q 200
fi
