{
  custom,
  symlinkJoin,
}:

symlinkJoin {
  name = "artcraft";

  paths = [
    custom.deckcraft
    custom.gridcraft
    custom.pdfcraft
    custom.photocraft
    custom.wordcraft
  ];

  meta = {
    description = "The ArtCraft suite";
    homepage = "https://getartcraft.com/apps";
    platforms = [ "x86_64-linux" ];
  };
}
