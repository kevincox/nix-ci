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
fi
source ~/.nix-profile/etc/profile.d/nix.sh
nix-channel --update

[ -f secrets/nix.conf ] && sudo install -Dm644 secrets/nix.conf /etc/nix/nix.conf

if [ -n "$SETUP_ONLY" ]; then
	exit 0
fi

nix-build "${flags[@]}"

if [ -n "$DEPLOY" -a -f secrets/b2-bucket ]; then
	nix-env -i /nix/store/jm3pazmq42x9lqz9dsvwrj16f74bwj2g-b2-nix-cache \
	           /nix/store/p5rdp7zlgfqryqnk80jjwnbc7b2f0x8v-backblaze-b2-0.6.2
	backblaze-b2 authorize_account $(cat secrets/b2-cred)
	b2-nix-cache $(cat secrets/b2-bucket) secrets/nix-cache-key
fi

if [ -n "$DEPLOY" ] && \
	nix-instantiate -E 'if import ./. ? marathon then [] else false' >&/dev/null
then
	nix-build -A marathon -o result-marathon
	args=(
		-O - --quiet --content-on-error
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
