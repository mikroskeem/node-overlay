#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl libxml2
set -euo pipefail

arches=(
	"darwin-arm64"
	"darwin-x64"
	"linux-arm64"
	"linux-x64"
)

declare -A nix_arches
nix_arches["darwin-arm64"]="aarch64-darwin"
nix_arches["linux-arm64"]="aarch64-linux"
nix_arches["darwin-x64"]="x86_64-darwin"
nix_arches["linux-x64"]="x86_64-linux"

collect_releases () {
	url="https://nodejs.org/en/feed/releases.xml"
	data="$(curl -s "${url}")"

	mapfile -d $'\n' -t lines < <(xmllint --noenc --xpath "/rss/channel/item/*[self::title or self::guid]" - <<< "${data}")

	i=0
	for (( ; i < ${#lines[@]}; )); do
		title="${lines[i++]}"
		guid="${lines[i++]}"
		title="$(xmllint --xpath "string(/title)" - <<< "${title}")"
		guid="$(xmllint --xpath "string(/guid)" - <<< "${guid}")"

		version="$(sed 's#.\+/blog/release/\(v.*\)#\1#' <<< "${guid}")"
		reltype="unknown"
		if grep -q -F "(Current)" <<< "${title}"; then
			reltype="current"
		elif grep -q -F "(LTS)" <<< "${title}"; then
			reltype="lts"
		fi

		echo -e "${version}\t${reltype}"
	done | sort
}

mapfile -d $'\n' -t releases < <(collect_releases)

# Grab all releases
for (( i=0; i < ${#releases[@]}; i++ )); do
	mapfile -d $'\t' -t _data /dev/stdin <<< "${releases[$i]}"
	version="${_data[0]}"
	reltype="$(echo "${_data[1]}" | tr -d '\n')"

	file="data/releases/.${version}.json.tmp"
	final_file="data/releases/${version}.json"
	if [ -f "${final_file}" ]; then
		continue
	fi

	echo "fetching ${version} (${reltype})"

	declare -A collected
	for arch in "${arches[@]}"; do
		nix_arch="${nix_arches[$arch]}"
		url="https://nodejs.org/dist/${version}/node-${version}-${arch}.tar.xz"

		# TODO: only >= 16.9.0 has Darwin arm64 builds
		if curl --silent --head "${url}" --show-error --write-out "%{http_code}" | grep -q "200"; then
			sha256="$(nix store prefetch-file --hash-type sha256 --json "${url}" | jq -r '.hash')"
			echo "${url} => ${sha256}"
			collected["${nix_arch}"]="$(echo -e "${url}\n${sha256}")"
		else
			echo "${url} => NONE"
			collected["${nix_arch}"]="null"
		fi
	done

	mkdir -p data/releases
	echo "{" > "${file}"
	for nix_arch in "${!collected[@]}"; do
		url="${collected[$nix_arch]}"
		if [ "${url}" = "null" ]; then
			echo "\"${nix_arch}\": null," >> "${file}"
		else
			mapfile -t _urldata /dev/stdin <<< "${url}"
			url="${_urldata[0]}"
			sha256="${_urldata[1]}"
			echo "\"${nix_arch}\": {\"url\": \"${url}\", \"sha256\": \"${sha256}\"}," >> "${file}"
		fi
	done
	echo "\"release_type\": \"${reltype}\"" >> "${file}"
	echo "}" >> "${file}"

	jq < "${file}" > "${final_file}"
	rm "${file}"
done

# Update all releases json
relfile="data/releases/._all.json.tmp"
relfile_final="data/releases/_all.json"
(cd data/releases; printf "%s\n" v*.json | sed 's#\.json##g') | jq --null-input --raw-input '[inputs | select(length>0)]' > "${relfile}"
mv "${relfile}" "${relfile_final}"

# vim: ft=bash
