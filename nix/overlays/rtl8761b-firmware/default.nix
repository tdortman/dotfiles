_:

_: prev: {
  rtl8761b-firmware = prev.rtl8761b-firmware.overrideAttrs (oldAttrs: {
    installPhase = (oldAttrs.installPhase or "") + ''
      mkdir -p $out/lib/firmware/rtl_bt

      install -m644 bt/rtkbt/Firmware/BT/rtl8761b_fw \
        $out/lib/firmware/rtl_bt/rtl8761bu_fw.bin

      install -m644 bt/rtkbt/Firmware/BT/rtl8761b_config \
        $out/lib/firmware/rtl_bt/rtl8761bu_config.bin
    '';
  });
}
