#!/usr/bin/env bash

CONFIG_DIR="$1"

if [ -z "$CONFIG_DIR" ]; then
    echo "Usage: $0 <config_dir>" >&2
    exit 1
fi

apply_qt_colors() {
    local config_dir="$1"
    local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
    local fallback_scheme="$data_home/color-schemes/DankMatugen.colors"

    update_qt_config() {
        local config_file="$1"
        local palette_file="$2"

        # qt5ct/qt6ct consume their native [ColorScheme] palette when available.
        # Fall back to the shared KDE color scheme for older installs.
        if [ ! -f "$palette_file" ]; then
            palette_file="$fallback_scheme"
        fi
        if [ ! -f "$palette_file" ]; then
            echo "Error: Qt color scheme not found for $config_file" >&2
            return 1
        fi

        mkdir -p "$(dirname "$config_file")"
        [ -f "$config_file" ] || : > "$config_file"

        if grep -q '^\[Appearance\]' "$config_file"; then
            if grep -q '^custom_palette=' "$config_file"; then
                sed -i 's/^custom_palette=.*/custom_palette=true/' "$config_file"
            else
                sed -i '/^\[Appearance\]/a custom_palette=true' "$config_file"
            fi
            if grep -q '^color_scheme_path=' "$config_file"; then
                sed -i "s|^color_scheme_path=.*|color_scheme_path=$palette_file|" "$config_file"
            else
                sed -i "/^\[Appearance\]/a color_scheme_path=$palette_file" "$config_file"
            fi
        else
            {
                echo ""
                echo "[Appearance]"
                echo "custom_palette=true"
                echo "color_scheme_path=$palette_file"
            } >> "$config_file"
        fi
    }

    qt5_applied=false
    qt6_applied=false

    if command -v qt5ct >/dev/null 2>&1; then
        update_qt_config "$config_dir/qt5ct/qt5ct.conf" "$config_dir/qt5ct/colors/matugen.conf"
        echo "Applied Qt5ct configuration"
        qt5_applied=true
    fi

    if command -v qt6ct >/dev/null 2>&1; then
        update_qt_config "$config_dir/qt6ct/qt6ct.conf" "$config_dir/qt6ct/colors/matugen.conf"
        echo "Applied Qt6ct configuration"
        qt6_applied=true
    fi

    if [ "$qt5_applied" = false ] && [ "$qt6_applied" = false ]; then
        echo "Warning: Neither qt5ct nor qt6ct found" >&2
        exit 1
    fi
}

apply_qt_colors "$CONFIG_DIR"

echo "Qt colors applied successfully"
