#! /bin/bash

nix-property-defined() {
	nix-instantiate -E "if import ./. ? $1 then [] else false" >&/dev/null
}

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
	nix-env -i /nix/store/b7034m9a5skv2p3fhpx8dizxsglw1n1a-b2-nix-cache \
	           /nix/store/k67pjp4ikjy48yr787rs5ggpv9f03jrc-backblaze-b2-0.6.2
	backblaze-b2 authorize_account $(cat secrets/b2-cred)
	b2-nix-cache $(cat secrets/b2-bucket) secrets/nix-cache-key
fi

if [ -n "$DEPLOY" ] && nix-property-defined marathon; then
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

if [ -n "$DEPLOY" ] && nix-property-defined docker; then
	nix-build -A docker -o result-docker
	docker push
fi
