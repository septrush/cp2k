#!/bin/bash -e
[ "${BASH_SOURCE[0]}" ] && SCRIPT_NAME="${BASH_SOURCE[0]}" || SCRIPT_NAME=$0
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_NAME")/.." && pwd -P)"

reflapack_ver="3.9.0"
reflapack_sha256="106087f1bb5f46afdfba7f569d0cbe23dacb9a07cd24733765a0e89dbe1ad573"
source "${SCRIPT_DIR}"/common_vars.sh
source "${SCRIPT_DIR}"/tool_kit.sh
source "${SCRIPT_DIR}"/signal_trap.sh
source "${INSTALLDIR}"/toolchain.conf
source "${INSTALLDIR}"/toolchain.env

[ -f "${BUILDDIR}/setup_reflapack" ] && rm "${BUILDDIR}/setup_reflapack"

REFLAPACK_CFLAGS=''
REFLAPACK_LDFLAGS=''
REFLAPACK_LIBS=''
! [ -d "${BUILDDIR}" ] && mkdir -p "${BUILDDIR}"
cd "${BUILDDIR}"

case "$with_reflapack" in
    __INSTALL__)
        echo "==================== Installing LAPACK ===================="
        pkg_install_dir="${INSTALLDIR}/lapack-${reflapack_ver}"
        install_lock_file="$pkg_install_dir/install_successful"
        if verify_checksums "${install_lock_file}" ; then
            echo "lapack-${reflapack_ver} is already installed, skipping it."
        else
            if [ -f lapack-${reflapack_ver}.tgz ] ; then
                echo "reflapack-${reflapack_ver}.tgz is found"
            else
                download_pkg ${DOWNLOADER_FLAGS} ${reflapack_sha256} \
                             https://www.cp2k.org/static/downloads/lapack-${reflapack_ver}.tgz
            fi
            echo "Installing from scratch into ${pkg_install_dir}"
            [ -d lapack-${reflapack_ver} ] && rm -rf lapack-${reflapack_ver}
            tar -xzf lapack-${reflapack_ver}.tgz
            cd lapack-${reflapack_ver}
            cat <<EOF > make.inc
SHELL    = /bin/sh
FORTRAN  = $FC
OPTS     = $FFLAGS -frecursive
DRVOPTS  = $FFLAGS -frecursive
NOOPT    = $FFLAGS -O0 -frecursive
LOADER   = $FC
LOADOPTS = $FFLAGS -Wl,--enable-new-dtags
TIMER    = INT_ETIME
CC       = $CC
CFLAGS   = $CFLAGS
ARCH     = ar
ARCHFLAGS= cr
RANLIB   = ranlib
XBLASLIB     =
BLASLIB      = ../../libblas.a
LAPACKLIB    = liblapack.a
TMGLIB       = libtmglib.a
LAPACKELIB   = liblapacke.a
EOF
            # lapack/blas build is *not* parallel safe (updates to the archive race)
            # Run first in parallel which will result most likely in an incomplete library
            make -j $NPROCS lib blaslib > make.log 2>&1
            # Complete library in non-parallel mode
            make -j 1 lib blaslib > make1.log 2>&1
            # no make install, so have to do this manually
            ! [ -d "${pkg_install_dir}/lib" ] && mkdir -p "${pkg_install_dir}/lib"
            cp libblas.a SRC/liblapack.a "${pkg_install_dir}/lib"
            cd ..
            write_checksums "${install_lock_file}" "${SCRIPT_DIR}/stage2/$(basename ${SCRIPT_NAME})"
        fi
        REFLAPACK_LDFLAGS="-L'${pkg_install_dir}/lib' -Wl,-rpath='${pkg_install_dir}/lib'"
        ;;
    __SYSTEM__)
        echo "==================== Finding LAPACK from system paths ===================="
        check_lib -lblas "lapack"
        check_lib -llapack "lapack"
        add_lib_from_paths REFLAPACK_LDFLAGS "liblapack.*" $LIB_PATHS
        ;;
    __DONTUSE__)
        ;;
    *)
        echo "==================== Linking LAPACK to user paths ===================="
        pkg_install_dir="$with_reflapack"
        check_dir "${pkg_install_dir}/lib"
        REFLAPACK_LDFLAGS="-L'${pkg_install_dir}/lib' -Wl,-rpath='${pkg_install_dir}/lib'"
        ;;
esac
if [ "$with_reflapack" != "__DONTUSE__" ] ; then
    REFLAPACK_LIBS="-llapack -lblas"
    if [ "$with_reflapack" != "__SYSTEM__" ] ; then
        cat <<EOF > "${BUILDDIR}/setup_reflapack"
prepend_path LD_LIBRARY_PATH "$pkg_install_dir/lib"
prepend_path LD_RUN_PATH "$pkg_install_dir/lib"
prepend_path LIBRARY_PATH "$pkg_install_dir/lib"
EOF
        cat "${BUILDDIR}/setup_reflapack" >> $SETUPFILE
    fi
    cat <<EOF >> "${BUILDDIR}/setup_reflapack"
export REFLAPACK_LDFLAGS="${REFLAPACK_LDFLAGS}"
export REFLAPACK_LIBS="${REFLAPACK_LIBS}"
export REF_MATH_LDFLAGS="\${REF_MATH_LDFLAGS} ${REFLAPACK_LDFLAGS}"
export REF_MATH_LIBS="\${REF_MATH_LIBS} ${REFLAPACK_LIBS}"
EOF
    if [ "$FAST_MATH_MODE" = reflapack ] ; then
        cat <<EOF >> setup_reflapack
export FAST_MATH_LDFLAGS="\${FAST_MATH_LDFLAGS} ${REFLAPACK_LDFLAGS}"
export FAST_MATH_LIBS="\${FAST_MATH_LIBS} ${REFLAPACK_LIBS}"
EOF
    fi
fi

load "${BUILDDIR}/setup_reflapack"
write_toolchain_env "${INSTALLDIR}"

cd "${ROOTDIR}"
report_timing "reflapack"
