#!/usr/bin/env bash

# exit if a variable is undefined, a command files, or a command in a pipeline fails
set -ueo pipefail

# ensure mix igniter.new is available
mix help | grep "mix igniter.new" >/dev/null || mix archive.install hex igniter_new --force

mkdir -p tmp
cd tmp
rm -rf test_mneme_install

mix igniter.new test_mneme_install --install mneme@path:../.. --yes

cd test_mneme_install

cat <<EOF >test_mneme_install_test.exs
defmodule TestMnemeInstallTest do
  use ExUnit.Case
  use Mneme

  test "succeeds if Mneme was installed properly" do
    auto_assert 1 <- 1
  end
end
EOF

mix mneme.watch --exit-on-success
exit $?
