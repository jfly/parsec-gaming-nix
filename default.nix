{ lib, addOpenGLRunpath, stdenv, fetchurl, alsaLib, dbus, ffmpeg_4, libGL, libpulseaudio, libva, libXfixes, gnome
, openssl, udev, xorg, wayland }:

stdenv.mkDerivation {
  pname = "parsec";
  version = "2021-01-12";

  src = fetchurl {
    url = "https://builds.parsecgaming.com/package/parsec-linux.deb";
    sha256 = "wwBy86TdrHaH9ia40yh24yd5G84WTXREihR+9I6o6uU=";
  };

  # The upstream deb package is out of date and doesn't work out of the box
  # anymore due to api.parsecgaming.com being down. Auto-updating doesn't work
  # because it doesn't patchelf the dynamic dependencies. Instead, "manually"
  # fetch the latest binaries.
  latest_appdata = fetchurl {
    url = "https://builds.parsecgaming.com/channel/release/appdata/linux/latest";
    sha256 = "N4FxUutU9risxP77vMKkT87rr1O8JMpNLiLRptpWac4=";
  };
  latest_parsecd_so = fetchurl {
    url ="https://builds.parsecgaming.com/channel/release/binary/linux/gz/parsecd-150-87.so";
    sha256 = "GNyn+jaxSVM5noUxyTAdSK2DriwbtQeG3Qyg25760nU=";
  };

  postPatch = ''
    cp $latest_appdata usr/share/parsec/skel/appdata.json
    cp $latest_parsecd_so usr/share/parsec/skel/parsecd-150-87.so
  '';

  nativeBuildInputs = [
    addOpenGLRunpath
  ];

  runtimeDependencies = [
    alsaLib (lib.getLib dbus) libGL libpulseaudio libva.out
    (lib.getLib openssl) (lib.getLib stdenv.cc.cc) (lib.getLib udev)
    xorg.libX11 xorg.libXcursor xorg.libXi xorg.libXinerama xorg.libXrandr
    xorg.libXScrnSaver wayland (lib.getLib ffmpeg_4)
    libXfixes
  ];

  unpackPhase = ''
    ar p "$src" data.tar.xz | tar xJ
  '';

  installPhase = ''
    mkdir -p $out/bin $out/libexec
    cp usr/bin/parsecd $out/libexec
    cp -r usr/share/parsec/skel $out/libexec
    # parsecd is a small wrapper binary which copies skel/* to ~/.parsec and
    # then runs from there. Unfortunately, it hardcodes the /usr/share/parsec
    # path, and patching that would be annoying. Instead, just reproduce the
    # install logic in a wrapper script.
    cat >$out/bin/parsecd <<EOF
    #! /bin/sh
    PATH=$PATH:${gnome.zenity}/bin
    mkdir -p \$HOME/.parsec
    ln -sf $out/libexec/skel/* \$HOME/.parsec
    exec $out/libexec/parsecd "\$@"
    EOF
    chmod +x $out/bin/parsecd
  '';

  postFixup = ''
    # We do not use autoPatchelfHook since we need runtimeDependencies rpath to
    # also be set on the .so, not just on the main executable.
    patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
        $out/libexec/parsecd
    rpath=""
    for dep in $runtimeDependencies; do
      rpath="$rpath''${rpath:+:}$dep/lib"
    done
    patchelf --set-rpath "$rpath" $out/libexec/parsecd
    patchelf --set-rpath "$rpath" $out/libexec/skel/*.so

    #<<< copied from nixpkgs::pkgs/development/libraries/ffmpeg/generic.nix >>>
    # Set RUNPATH so that libnvcuvid and libcuda in /run/opengl-driver(-32)/lib can be found.
    # See the explanation in addOpenGLRunpath.
    addOpenGLRunpath $out/libexec/parsecd
    addOpenGLRunpath $out/libexec/skel/*.so
  '';

  meta = with lib; {
    description = "Remotely connect to a gaming PC for a low latency remote computing experience";
    homepage = "https://parsecgaming.com/";
    license = licenses.unfree;
    maintainers = with maintainers; [ delroth ];
  };
}
