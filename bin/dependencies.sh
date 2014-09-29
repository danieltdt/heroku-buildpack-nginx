#!/usr/bin/env bash

jq="$(cd $(dirname $0); cd ..; pwd)/vendor/jq"

ROOT=${ROOT:-/app}
DEPENDENCIES_CACHE_DIR=${DEPENDENCIES_CACHE_DIR:?DEPENDENCIES_CACHE_DIR is not defined!}

# Create metadata folder
mkdir -p "$DEPENDENCIES_CACHE_DIR"

assert_json_value() {
  # assert_json_value <json-or-value> <error-message>
  if [ "x$1" == "x" ] || [ "x$1" == "xnull" ]; then
    echo $2 >&2
    exit 1
  fi
}

extract_dependency_file() {
  # extract_dependency_file <compressed-file> <location>
  rm -rf $2
  mkdir -p $2
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
  local name=$(echo "$*"     | $jq -c -r '.name')
  local md5=$(echo "$*"      | $jq -c -r '.md5')
  local url=$(echo "$*"      | $jq -c -r '.url')
  local dep_root=$(echo "$*" | $jq -c -r '.dependency_root // ""')
  local path="$(echo "$*"    | $jq -c -r '.path // "/vendor"')/$name"
  local install="$(echo "$*" | $jq -c -r '.install')"

  local extract_dir="${ROOT%/}/${path#/}"
  local checksum="$md5 $name"

  assert_json_value $name ".name is required"
  assert_json_value $md5  ".md5 is required"
  assert_json_value $url  ".url is required"

  # Create cache dir (if not exists)
  mkdir -p "$DEPENDENCIES_CACHE_DIR/$name"

  # Check if already installed
  local is_cached='no'
  local cached_checksum=$(cat "$DEPENDENCIES_CACHE_DIR/$name/checksum" 2> /dev/null | head -n1)
  if [[ $cached_checksum == $checksum ]]; then
    echo "  $name is cached"
    is_cached='yes'
  else
    echo "  $name not cached; downloading"
    rm -f "$DEPENDENCIES_CACHE_DIR/$name/*"
  fi

  if [[ $is_cached == 'yes' ]]; then
    cp "$DEPENDENCIES_CACHE_DIR/$name/$name" .
  else
    # Download
    curl -L $url -s -o $name

    # Check download
    echo $checksum | md5sum --check --quiet --status -
    if [[ $? -ne 0 ]]; then
      echo "Checksum md5 did not match; exiting" >&2
      exit 1
    fi
    echo "  Checksum OK"
  fi

  # Extract
  extract_dependency_file "$name" "$extract_dir"

  # Get extracted root dir
  local extracted_root_dir=''
  if [[ "x$dep_root" == "x" ]]; then
    extracted_root_dir=$(find ${extract_dir%/}/* -maxdepth 0 -type d | head -n1)
  else
    extracted_root_dir="${extract_dir%/}/${dep_root#/}"
  fi

  # Install
  if [ "x$install" != "x" ] && [ "x$install" != "xnull" ]; then
    local THIS="$extracted_root_dir"
    install=$(echo $install | sed -e "s#\$ROOT#$ROOT#g")
    install=$(echo $install | sed -e "s#\$THIS#$THIS#g")
    echo "Installing $name"
    echo "  $install"
    (cd "$extracted_root_dir"; eval ${install[*]})
  fi

  # Save installed dependency data & metadata
  cp "$name" "$DEPENDENCIES_CACHE_DIR/$name/"
  echo $checksum > "$DEPENDENCIES_CACHE_DIR/$name/checksum"
  echo $extracted_root_dir > "$DEPENDENCIES_CACHE_DIR/$name/root-path"

  # Remove downloaded file
  rm $name
}

run_postdeploy_script() {
  local name=${1:?dependency name is required}
  local script="${*:2}"

  if [[ ! -d "$DEPENDENCIES_CACHE_DIR/$name" ]]; then
    echo "Dependency not installed; exiting" >&2
    exit 1
  fi

  local extracted_root_dir=$(cat $DEPENDENCIES_CACHE_DIR/$name/root-path)
  local THIS="$extracted_root_dir"
  script=$(echo $script | sed -e "s#\$ROOT#$ROOT#g")
  script=$(echo $script | sed -e "s#\$THIS#$THIS#g")
  echo "Postdeploy $name"
  echo "  $script"
  (cd $extracted_root_dir; eval ${script[*]})
}

get_installed_path() {
  local name=${1:?dependency name is required}

  echo $(cat "$DEPENDENCIES_CACHE_DIR/$name/root-path")
}

install_dependencies() {
  while read -r dep_json; do
    install_dependency $dep_json
  done < <( cat $1 | $jq -c -r '.dependencies // [] | .[]')
}

run_postdeploy_scripts() {
  while read -r dep_json; do
    if [ "x$(echo $dep_json | $jq -c -r '.postdeploy // ""')" == "x" ]; then
      continue
    fi

    run_postdeploy_script $(echo $dep_json | $jq -c -r '[.name, .postdeploy] | join(" ")')
  done < <( cat $1 | $jq -c -r '.dependencies // [] | .[]')
}
