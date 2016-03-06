with import <nixpkgs> {};

stdenv.mkDerivation {
	name = "test";
	
	buildInputs = [ ruby ];
	
	src = builtins.filterSource (name: type: false) ./.;
	
	installPhase = ''
		ruby -e 'File.write ARGV[0], "content"' "$out"
	'';
}
