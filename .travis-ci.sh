#!/bin/bash -xue

PATH=~/ocaml/bin:$PATH; export PATH
OPAMYES="true"; export OPAMYES

has-label () {
    local label="$1"
    local API_URL=https://api.github.com/repos/$TRAVIS_REPO_SLUG/issues/$TRAVIS_PULL_REQUEST/labels
    test -n "$(curl $API_URL | grep $label)"
}

file-has-changed () {
    local file="$1"
    local cur_head=${TRAVIS_COMMIT_RANGE%%...*}
    local pr_head=${TRAVIS_COMMIT_RANGE##*...}
    local merge_base=$(git merge-base $cur_head $pr_head)
    if git diff --name-only --exit-code $merge_base..$pr_head \
           "$file" > /dev/null; then
        false
    else
        true
    fi
}

if [[ "$CI_KIND" == changes ]]; then
    if [[ "$TRAVIS_EVENT_TYPE" == pull_request ]]; then
        cat<<EOF
------------------------------------------------------------------------
This test checks that the CHANGES.md file has been modified by the
pull request. Most contributions should come with a message in the
CHANGES.md.

Some very minor changes (typo fixes for example) may not need a
Changes entry. In this case, you may explicitly disable this test by
by using the "no-change-entry-needed" label on the github pull
request.
------------------------------------------------------------------------
EOF
        # check that CHANGES.md has been modified
        if file-has-changed CHANGES.md || has-label no-change-entry-required; then
            echo pass
        else
            exit 1
        fi
    fi
    exit 0
fi

TARGET="$1"; shift

case "$TARGET" in
  prepare)
    echo -en "travis_fold:start:ocaml\r"
    if [ ! -e ~/ocaml/cached-version -o "$(cat ~/ocaml/cached-version)" != "$OCAML_VERSION.$OCAML_RELEASE" ] ; then
      rm -rf ~/ocaml
      mkdir -p ~/ocaml/src
      cd ~/ocaml/src
      wget http://caml.inria.fr/pub/distrib/ocaml-$OCAML_VERSION/ocaml-$OCAML_VERSION.$OCAML_RELEASE.tar.gz
      tar -xzf ocaml-$OCAML_VERSION.$OCAML_RELEASE.tar.gz
      cd ocaml-$OCAML_VERSION.$OCAML_RELEASE
      ./configure -prefix ~/ocaml
      make world.opt
      make install
      cd ../..
      rm -rf src
      echo "$OCAML_VERSION.$OCAML_RELEASE" > ~/ocaml/cached-version
    fi
    echo -en "travis_fold:end:ocaml\r"
    if [ $WITH_OPAM -eq 1 ] ; then
      echo -en "travis_fold:start:opam.init\r"
      if [ "$TRAVIS_OS_NAME" = "osx" ] ; then
        brew update
        brew install aspcud
        PREFIX=/Users/travis
      else
        PREFIX=/home/travis
      fi
      if [ ! -e ~/ocaml/bin/opam -o ! -e ~/.opam/lock -o "$OPAM_RESET" = "1" ] ; then
        mkdir ~/ocaml/src
        cd ~/ocaml/src
        wget https://github.com/ocaml/opam/releases/download/2.0.0-rc4/opam-full-2.0.0.tar.gz
        tar -xzf opam-full-2.0.0.tar.gz
        cd opam-full-2.0.0
        ./configure --prefix=$PREFIX/ocaml
        make lib-ext
        make all
        make install
        cd ../..
        rm -rf src
        rm -rf ~/.opam
        opam init --disable-sandboxing
        eval $(opam config env)
        opam install ocamlfind utop ppxlib odoc menhir ocaml-migrate-parsetree js_of_ocaml-ppx js_of_ocaml-compiler
        opam remove dune jbuilder \
             `opam list --depends-on jbuilder --installed --short` \
             `opam list --depends-on dune     --installed --short`
        if opam info dune &> /dev/null; then
            opam remove dune `opam list --depends-on dune --installed --short`
        fi
      fi
      cp -a ~/.opam ~/.opam-start
      echo -en "travis_fold:end:opam.init\r"
    fi
  ;;
  build)
    UPDATE_OPAM=0
    if [ $WITH_OPAM -eq 1 ] ; then
      echo -en "travis_fold:start:opam.deps\r"
      DATE=$(date +%Y%m%d)
      eval $(opam config env)
      for pkg in $(opam pin list --short); do
        UPDATE_OPAM=1
        opam pin remove $pkg --no-action
        opam remove $pkg || true
      done
      if [ ! -e ~/.opam/last-update ] || [ $(cat ~/.opam/last-update) != $DATE ] ; then
        opam update
        echo $DATE> ~/.opam/last-update
        UPDATE_OPAM=1
        opam upgrade
      fi
      opam list
      echo "version: \"1.0+dev$DATE\"" >> dune.opam
      opam pin add dune . --no-action
      opam install ocamlfind utop ppxlib odoc ocaml-migrate-parsetree js_of_ocaml-ppx js_of_ocaml-compiler
      echo -en "travis_fold:end:opam.deps\r"
    fi
    echo -en "travis_fold:start:dune.bootstrap\r"
    ocaml bootstrap.ml
    echo -en "travis_fold:end:dune.bootstrap\r"
    ./boot.exe --subst
    echo -en "travis_fold:start:dune.boot\r"
    ./boot.exe
    echo -en "travis_fold:end:dune.boot\r"
    if [ $WITH_OPAM -eq 1 ] ; then
      _build_bootstrap/install/default/bin/dune runtest && \
      _build_bootstrap/install/default/bin/dune build @test/blackbox-tests/runtest-js && \
      ! _build_bootstrap/install/default/bin/dune build @test/fail-with-background-jobs-running
      RESULT=$?
      if [ $UPDATE_OPAM -eq 0 ] ; then
        rm -rf ~/.opam
        mv ~/.opam-start ~/.opam
      fi
      exit $RESULT
    fi
  ;;
  *)
    echo "bad command $TARGET">&2; exit 1
esac
