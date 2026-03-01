let
  pubKey = "age1r3ee8yzrvhsqzpur68xpuheg8g66q3g4eu8dk4eft9xyh0nczdhqpn3grr";
in
{
  "restic-password.age".publicKeys = [ pubKey ];
  "nextdns-resolved.conf.age".publicKeys = [ pubKey ];
  "airvpn-privatekey.age".publicKeys = [ pubKey ];
  "airvpn-presharedkey.age".publicKeys = [ pubKey ];
}
