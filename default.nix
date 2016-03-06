with import <nixpkgs> {};

stdenv.mkDerivation {
	name = "test";
	
	buildInputs = [ ruby ];
	
	installPhase = ''
		ruby -e 'File.write ARGV[0], "content"' "$out"
	'';
}
