#!/usr/bin/env bash
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
	url="https://nodejs.org/dist/"

	curl -s "${url}" | htmlq --attribute href a | grep '^v.*\d*/$' | sed 's#/$##' | while read -r version; do
		major="$(sed 's/^v//' <<< "${version}" | cut -d. -f1)"

		reltype="unknown"

		# Even numbered major versions are LTS - https://nodejs.org/en/about/releases/
		if [ "$(( major % 2 ))" = "0" ]; then
			reltype="lts"
		elif ! [ "${major}" = "0" ]; then # != v0.x
			reltype="current"
		fi

		echo -e "${version}\t${reltype}"
	done | sort -V
}

mapfile -d $'\n' -t releases < <(collect_releases)

# Grab all releases
for (( i=0; i < ${#releases[@]}; i++ )); do
	mapfile -d $'\t' -t _data /dev/stdin <<< "${releases[$i]}"
	version="${_data[0]}"
	reltype="$(echo "${_data[1]}" | tr -d '\n')"

	file="data/releases/.${version}.json.tmp"
	final_file="data/releases/${version}.json"

	# uncomment if need to rebuild
	if [ -f "${final_file}" ]; then
		continue
	fi

	echo "fetching ${version} (${reltype})"

	declare -A collected
	for arch in "${arches[@]}"; do
		nix_arch="${nix_arches[$arch]}"

		existing_url="$(test -f "${final_file}" && jq -r ".[\"${nix_arch}\"]" < "${final_file}" || true)"
		echo "existing url='${existing_url}'"
		if [ -f "${final_file}" ] && ! [ "${existing_url}" = "null" ]; then
			collected["${nix_arch}"]="$(jq -r ".[\"${nix_arch}\"] | \"\\(.url)\n\\(.sha256)\"" < "${final_file}")"
			continue
		fi
		# TODO: only >= 16.9.0 has Darwin arm64 builds

		url=""
		for ext in xz gz; do
			url="https://nodejs.org/dist/${version}/node-${version}-${arch}.tar.${ext}"
			if curl --silent --head "${url}" --show-error --write-out "%{http_code}" | grep -q "200"; then
				break
			fi
			url=""
		done

		sha256=""
		result=0
		if [ -n "${url}" ]; then
			set +e
			sha256="$(nix store prefetch-file --hash-type sha256 --json "${url}" | jq -r '.hash')"
			result=$?
			set -e
		fi

		if [ -z "${url}" ] || ! [ "${result}" -eq 0 ]; then
			echo "(${nix_arch} ${version}) => NONE"
			collected["${nix_arch}"]="null"
			continue
		fi

		echo "${url} => ${sha256}"
		collected["${nix_arch}"]="$(echo -e "${url}\n${sha256}")"
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
(cd data/releases; printf "%s\n" v*.json | sed 's#\.json##g' | sort -V) | jq --null-input --raw-input '[inputs | select(length>0)]' > "${relfile}"
mv "${relfile}" "${relfile_final}"

# vim: ft=bash
