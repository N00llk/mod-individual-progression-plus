#!/usr/bin/env bash
set -euo pipefail

repo=/work
locale="${PATCH_LOCALE:-ruRU}"
archive="${PATCH_DBC_ARCHIVE:-/work/optional/client-patch-dbc.7z}"
output_name="${PATCH_OUTPUT_NAME:-patch-${locale}-Z.MPQ}"

if [[ ! "$locale" =~ ^[A-Za-z]{4}$ ]]; then
    echo "Invalid locale: $locale" >&2
    exit 2
fi
if [[ ! "$output_name" =~ ^[A-Za-z0-9._-]+\.MPQ$ ]]; then
    echo "Invalid output filename: $output_name" >&2
    exit 2
fi
if [[ ! -f "$archive" ]]; then
    echo "DBC source archive not found: $archive" >&2
    exit 2
fi

lower_locale="$(printf '%s' "$locale" | tr '[:upper:]' '[:lower:]')"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
dbc_root="$tmp/dbc"
build_root="$tmp/build"
mkdir -p "$dbc_root" "$build_root/addon/IPTalents" "$build_root/stage"

echo "Extracting DBC source archive for $locale"
7z x -bd -y "$archive" "-o$dbc_root" >/dev/null
dbc_source="$dbc_root/$lower_locale"
for name in Spell.dbc SkillLineAbility.dbc SkillLine.dbc; do
    if [[ ! -f "$dbc_source/$name" ]]; then
        echo "Missing $lower_locale/$name in $archive" >&2
        echo "The archive must contain $lower_locale/{Spell,SkillLineAbility,SkillLine}.dbc" >&2
        exit 2
    fi
done

addon_source="$repo/data/client/addon/IPTalents"
addon_stage="$build_root/addon/IPTalents"
cp -a "$addon_source/." "$addon_stage/"
generator="$repo/tools/gen_era_talents.py"
dataset="$repo/data/talents/vanilla/mage.yaml"
export PYTHONPATH="$repo/tools${PYTHONPATH:+:$PYTHONPATH}"

echo 'Generating locale addon data'
ERA_TALENT_LOCALE=enUS python3 "$generator" --lua "$dataset" \
    -o "$addon_stage/data/generated/MageVanilla.lua"
ERA_TALENT_LOCALE=ruRU python3 "$generator" --lua "$dataset" \
    -o "$addon_stage/data/generated/MageVanillaRu.lua"

spell_dbc="$build_root/stage/Spell.dbc"
skill_ability_dbc="$build_root/stage/SkillLineAbility.dbc"
python3 "$repo/tools/build_client_dbc.py" \
    --dataset "$dataset" --base-dbc "$dbc_source/Spell.dbc" \
    --out "$spell_dbc"
python3 "$repo/tools/build_client_skilllineability.py" \
    --dataset "$dataset" --base-dbc "$dbc_source/SkillLineAbility.dbc" \
    --out "$skill_ability_dbc"

manifest="$build_root/manifest.tsv"
{
    printf 'DBFilesClient\\Spell.dbc\t%s\n' "$spell_dbc"
    printf 'DBFilesClient\\SkillLineAbility.dbc\t%s\n' "$skill_ability_dbc"
    printf 'DBFilesClient\\SkillLine.dbc\t%s\n' "$dbc_source/SkillLine.dbc"
    printf 'Interface\\AddOns\\IPTalents\\IPTalents.toc\t%s\n' \
        "$addon_stage/IPTalents.toc"

    while IFS= read -r line || [[ -n "$line" ]]; do
        entry="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -z "$entry" ]] && continue
        [[ "$entry" == \#\#* ]] && continue
        relative="$(printf '%s' "$entry" | sed 's|\\|/|g')"
        source="$addon_stage/$relative"
        if [[ ! -f "$source" ]]; then
            echo "TOC entry is missing from addon: $entry" >&2
            exit 2
        fi
        internal="Interface\\AddOns\\IPTalents\\${relative//\//\\}"
        printf '%s\t%s\n' "$internal" "$source"
    done < "$addon_stage/IPTalents.toc"
} > "$manifest"

archive_out="$tmp/$output_name"
echo "Packing $output_name"
"$MPQPACK" manifest "$archive_out" "$manifest"

for internal in \
    'DBFilesClient\Spell.dbc' \
    'DBFilesClient\SkillLineAbility.dbc' \
    'DBFilesClient\SkillLine.dbc' \
    'Interface\AddOns\IPTalents\IPTalents.toc'; do
    "$MPQPACK" verify "$archive_out" "$internal"
done

"$MPQREAD" verify "$archive_out" 'DBFilesClient\SkillLine.dbc' \
    "$dbc_source/SkillLine.dbc"

mkdir -p /output
mv -f "$archive_out" "/output/$output_name"
sha256sum "/output/$output_name"
echo "Built patch: /output/$output_name"
