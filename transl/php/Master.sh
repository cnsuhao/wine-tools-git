#!/bin/bash

# Main script - change 'config' to setup input/output directories

if [ ! -f ./config ]; then
    echo "Config file not found in current directory. Copy config-example to config and edit the configuration"
    exit 1
fi

. ./config

if [ -x ./local-prehook.sh ]; then
    ./local-prehook.sh
fi

function die {
    echo $1 >>"$WORKDIR/run.log"
    cat "$WORKDIR/run.log"
    exit 1
}

mv -f $WORKDIR/run.log $WORKDIR/run.log.old

if [ "$PREPARE_TREES" -eq 1 ]; then
    # Prepare the trees (they may be the same or different)
    if [ "x$NOVERBOSE" = "x" ]; then
        echo -n "Preparing tree(s)..."
    fi
    if [ ! -f "$WRCROOT/Makefile" ]; then
        (cd $WRCROOT && $SOURCEROOT/configure)
    fi
    make -C "$WRCROOT" depend >/dev/null 2>>"$WORKDIR/run.log" || die "make depend in wrc tree failed"
    make -C "$WRCROOT" tools >/dev/null 2>>"$WORKDIR/run.log" || die "make tools in wrc tree failed"
    make -C "$BUILDROOT" depend >/dev/null 2>>"$WORKDIR/run.log" || die "make depend in build tree failed"
    make -C "$BUILDROOT" include/stdole2.tlb >/dev/null 2>>"$WORKDIR/run.log" || die "make depend in build tree failed"
    if [ "x$NOVERBOSE" = "x" ]; then
        echo " done"
    fi
fi

# Do cleanup for new run
rm -Rf $WORKDIR/data
mkdir $WORKDIR/data
mkdir $WORKDIR/data/res

# Analyze all the Makefiles
php ./parse_resfiles.php -S "$SOURCEROOT" -T "$BUILDROOT" -t "$WRCROOT" -w "$WORKDIR/data" 2>>"$WORKDIR/run.log" || exit

# Show any changes in the log
diff -u $WORKDIR/run.log.old $WORKDIR/run.log

# Copy the new data from the working directory to the PHP scripts input
mv -f $DESTDIR/data $DESTDIR/data.old
mv -f $WORKDIR/data $DESTDIR/data
cp -f $WORKDIR/run.log $DESTDIR/data/run.log

# Deleting can take a bit longer so we do it after the new version is set up
rm -Rf $DESTDIR/data.old

# Optional hooks
if [ -x ./local-posthook.sh ]; then
    ./local-posthook.sh
fi
