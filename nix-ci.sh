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

flags=(
	--fallback
	--show-trace
)
if [ -n "$DEPLOY" ]; then
	flags+=(-j2)
fi

if [ '!' -d /nix ]; then
	echo "# INSTALLING NIX"
	curl -fsS https://nixos.org/nix/install | bash
	source ~/.nix-profile/etc/profile.d/nix.sh
fi
nix-channel --update

[ -f secrets/nix.conf ] && sudo install -Dm644 secrets/nix.conf /etc/nix/nix.conf

nix-build "${flags[@]}" -A ${BUILD_ATTR:-all}

if [ -n "$DEPLOY" -a -f secrets/b2-bucket ]; then
	nix-env -i /nix/store/vbdwzacckpazr734l6i0wdw83fkb5j0p-b2-nix-cache
	nix-env -iA nixpkgs.backblaze-b2
	backblaze-b2 authorize_account $(cat secrets/b2-cred)
	b2-nix-cache $(cat secrets/b2-bucket) secrets/nix-cache-key
fi

if [ -n "$DEPLOY" ] && \
	nix-instantiate -E 'if import ./. ? marathon then [] else false'
then
	nix-build -A marathon -o result-marathon
	args=(
		-o - --quiet --content-on-error
		--method PUT
		--header 'Content-Type: application/json'
		--body-file result-marathon
		"$(cat secrets/marathon)/v2/apps"
	)
	[ -f secrets/marathon.ca.crt ] && args+=(--ca-certificate secrets/marathon.ca.crt)
	[ -f secrets/marathon.crt ]    && args+=(--certificate secrets/marathon.crt)
	[ -f secrets/marathon.key ]    && args+=(--private-key secrets/marathon.key)
	
	# Make request.
	wget "${args[@]}"
fi
