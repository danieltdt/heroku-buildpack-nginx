#!/usr/bin/env bash

jq="$(cd $(dirname $0); cd ..; pwd)/vendor/jq"

ROOT=${ROOT:-/app}

assert_json_value() {
  if [[ "x$1" == "x" || "x$1" == "xnull" ]]; then
    echo $2 >&2
    exit 1
  fi
}

extract_dependency_file() {
  # extract <compressed-file> <location>
  case "$1" in
    *.tar.gz)  tar xzf $1 -C $2 ;;
    *.tgz)     tar xzf $1 -C $2 ;;
    *.tar.bz2) tar xjf $1 -C $2 ;;
    *.zip)     unzip $1 -d $2 ;;
    *)
      echo "cannot extract file $1" >&2
      exit 1
      ;;
  esac
}

install_dependency() {
  local name=    $(echo $1 | $jq -r '.name')
  local md5=     $(echo $1 | $jq -r '.md5')
  local url=     $(echo $1 | $jq -r '.url')
  local path=    $(echo $1 | $jq -r '.path')
  local install= $(echo $1 | $jq -r '.install')

  assert_json_value $name ".name is required"
  assert_json_value $md5  ".md5 is required"
  assert_json_value $url  ".url is required"
  assert_json_value $path ".path is required"

  # Download
  curl -L $url -s -o $name

  # Check download
  echo "$md5 $name" | md5sum --check --quiet --status -
  if [[ $? -ne 0 ]]; then
    echo "md5 did not match; exiting" >&2
    exit 1
  fi

  # Extract
  extract_dependency_file "$name" "$ROOT/$path"

  # Install
  if [[ "x$install" != "x" && "x$install" != "xnull" ]]; then
    echo "Installing $name"
    echo $install
    (cd $ROOT/$path; $install)
  fi

  # Remove downloaded file
  rm $name
}

run_postdeploy_script() {
  local name=   $(echo $1 | $jq -r '.name')
  local path=   $(echo $1 | $jq -r '.path')
  local script= $(echo $1 | $jq -r 'postdeploy')

  assert_json_value $name ".name is required"
  if [[ ! -d "$path" ]]; then
    echo "Dependency not installed" >&2
    exit 1
  fi

  if [[ "x$script" != "x" && "x$script" != "xnull" ]]; then
    echo "Postdeploy $name"
    echo $script
    (cd $ROOT/$path; $script)
  fi
}

install_dependencies() {
  while read -r dep_json; do
    install_dependency $dep_json
  done < <( cat $1 | $jq -r '.dependencies[]')
}

run_postdeploy_scripts() {
  while read -r dep_json; do
    run_postdeploy_script $dep_json
  done < <( cat $1 | $jq -r '.dependencies[]')
}
