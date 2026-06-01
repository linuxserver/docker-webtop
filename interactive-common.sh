#!/usr/bin/env bash

shared_to_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

shared_prompt_text_default() {
    local __var_name="$1"
    local prompt="$2"
    local default_value="$3"
    local answer

    read -r -p "${prompt} (default: ${default_value}): " answer
    printf -v "${__var_name}" '%s' "${answer:-$default_value}"
}

shared_prompt_optional_text() {
    local __var_name="$1"
    local prompt="$2"
    local answer

    read -r -p "${prompt}: " answer
    printf -v "${__var_name}" '%s' "${answer}"
}

shared_prompt_yes_no_default() {
    local prompt="$1"
    local default_choice="$2"
    local suffix=""
    local default_answer=""
    local answer=""
    local normalized=""

    case "${default_choice}" in
        yes)
            suffix="Y/n"
            default_answer="y"
            ;;
        no)
            suffix="y/N"
            default_answer="n"
            ;;
        *)
            echo "Internal error: invalid yes/no default '${default_choice}'." >&2
            exit 1
            ;;
    esac

    while true; do
        read -r -p "${prompt} (${suffix}): " answer
        answer="${answer:-$default_answer}"
        normalized=$(shared_to_lower "${answer}")
        case "${normalized}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *)
                echo "Please enter y or n, then press Enter."
                ;;
        esac
    done
}

shared_prompt_choice_default() {
    local __var_name="$1"
    local prompt="$2"
    local default_value="$3"
    local pattern="$4"
    local answer

    while true; do
        read -r -p "${prompt} (default: ${default_value}): " answer
        answer="${answer:-$default_value}"
        if [[ "${answer}" =~ ${pattern} ]]; then
            printf -v "${__var_name}" '%s' "${answer}"
            return 0
        fi
        echo "Invalid selection: ${answer}"
    done
}

shared_prompt_required_text() {
    local __var_name="$1"
    local prompt="$2"
    local answer

    while true; do
        read -r -p "${prompt}: " answer
        if [[ -n "${answer}" ]]; then
            printf -v "${__var_name}" '%s' "${answer}"
            return 0
        fi
        echo "A value is required."
    done
}

shared_normalize_arch_or_die() {
    local input="$1"
    case "$(shared_to_lower "${input}")" in
        amd64|x86_64)
            printf '%s' "amd64"
            ;;
        arm64|aarch64)
            printf '%s' "arm64"
            ;;
        *)
            echo "Unsupported architecture: ${input}" >&2
            exit 1
            ;;
    esac
}

shared_apply_locale_from_timezone() {
    local timezone="${1:-UTC}"

    case "${timezone}" in
        Asia/Tokyo)
            BUILD_LANGUAGE="ja"
            TIMEZONE="Asia/Tokyo"
            RUNTIME_TZ="Asia/Tokyo"
            RUNTIME_LANG="ja_JP.UTF-8"
            RUNTIME_LC_ALL="ja_JP.UTF-8"
            RUNTIME_LANGUAGE="ja_JP:ja"
            ;;
        *)
            BUILD_LANGUAGE="en"
            TIMEZONE="UTC"
            RUNTIME_TZ="UTC"
            RUNTIME_LANG="en_US.UTF-8"
            RUNTIME_LC_ALL="en_US.UTF-8"
            RUNTIME_LANGUAGE="en_US:en"
            ;;
    esac
}

shared_collect_interactive_settings() {
    local default_encoder_choice="1"
    local default_docker_mode_choice="1"
    local default_lang_choice="en"
    local default_gpu_choice="1"
    local encoder_choice=""
    local docker_mode_choice=""
    local gpu_choice=""
    local arch_choice=""
    local lang_choice=""
    local default_mac_choice="no"

    case "$(shared_to_lower "${ENCODER:-software}")" in
        nvidia) default_encoder_choice="2" ;;
        nvidia-wsl) default_encoder_choice="3" ;;
        intel) default_encoder_choice="4" ;;
        amd) default_encoder_choice="5" ;;
        *) default_encoder_choice="1" ;;
    esac

    case "$(shared_to_lower "${DOCKER_MODE:-dind}")" in
        dood) default_docker_mode_choice="2" ;;
        *) default_docker_mode_choice="1" ;;
    esac

    case "${TIMEZONE:-UTC}" in
        Asia/Tokyo) default_lang_choice="ja" ;;
        *) default_lang_choice="en" ;;
    esac

    if [[ "${GPU_ALL:-false}" == "true" || "${DOCKER_GPUS:-}" == "all" ]]; then
        default_gpu_choice="2"
    elif [[ -n "${GPU_NUMS:-}" || "${DOCKER_GPUS:-}" == device=* ]]; then
        default_gpu_choice="3"
    fi

    case "${IS_MAC:-false}" in
        true) default_mac_choice="yes" ;;
        *) default_mac_choice="no" ;;
    esac

    echo "========================================"
    echo "Configuration Questions"
    echo "========================================"
    echo ""

    echo "1. Container Settings"
    echo "---------------------"
    shared_prompt_text_default CONTAINER_NAME "Container name" "${CONTAINER_NAME}"
    shared_prompt_text_default UBUNTU_VERSION "Ubuntu version (22.04, 24.04, or 26.04)" "${UBUNTU_VERSION}"
    shared_prompt_text_default arch_choice "Target architecture (amd64 or arm64)" "${TARGET_ARCH}"
    TARGET_ARCH="$(shared_normalize_arch_or_die "${arch_choice}")"
    shared_prompt_choice_default docker_mode_choice "Docker mode [1=dind, 2=dood]" "${default_docker_mode_choice}" '^[1-2]$'
    case "${docker_mode_choice}" in
        2) DOCKER_MODE="dood" ;;
        *) DOCKER_MODE="dind" ;;
    esac
    echo ""

    echo "2. Encoder and GPU Configuration"
    echo "--------------------------------"
    echo "Select encoder type:"
    echo "  1) Software (CPU)"
    echo "  2) NVIDIA (NVENC)"
    echo "  3) NVIDIA WSL2 (NVENC)"
    echo "  4) Intel (VA-API)"
    echo "  5) AMD (VA-API)"
    shared_prompt_choice_default encoder_choice "Select [1-5]" "${default_encoder_choice}" '^[1-5]$'

    DRI_NODE=""
    case "${encoder_choice}" in
        2)
            ENCODER="nvidia"
            ;;
        3)
            ENCODER="nvidia-wsl"
            ;;
        4)
            ENCODER="intel"
            echo ""
            echo "DRI Node Configuration"
            echo "----------------------"
            echo "Leave empty to auto-detect the render node."
            if [[ -n "${DRI_NODE}" ]]; then
                shared_prompt_text_default DRI_NODE "Specify DRI node (e.g. /dev/dri/renderD129)" "${DRI_NODE}"
            else
                shared_prompt_optional_text DRI_NODE "Specify DRI node (e.g. /dev/dri/renderD129, leave empty to auto-detect)"
            fi
            ;;
        5)
            ENCODER="amd"
            echo ""
            echo "DRI Node Configuration"
            echo "----------------------"
            echo "Leave empty to auto-detect the render node."
            if [[ -n "${DRI_NODE}" ]]; then
                shared_prompt_text_default DRI_NODE "Specify DRI node (e.g. /dev/dri/renderD129)" "${DRI_NODE}"
            else
                shared_prompt_optional_text DRI_NODE "Specify DRI node (e.g. /dev/dri/renderD129, leave empty to auto-detect)"
            fi
            ;;
        *)
            ENCODER="software"
            ;;
    esac

    GPU_ALL="false"
    GPU_NUMS=""
    DOCKER_GPUS=""
    echo ""

    echo "Docker GPU Selection"
    echo "--------------------"
    echo "Select Docker GPU attachment (independent from encoder):"
    echo "  1) None"
    echo "  2) All GPUs (--gpus all)"
    echo "  3) Specific devices (--gpus device=...)"
    shared_prompt_choice_default gpu_choice "Select [1-3]" "${default_gpu_choice}" '^[1-3]$'
    case "${gpu_choice}" in
        2)
            GPU_ALL="true"
            DOCKER_GPUS="all"
            ;;
        3)
            shared_prompt_required_text GPU_NUMS "Enter GPU device numbers (comma-separated, e.g. 0,1)"
            DOCKER_GPUS="device=${GPU_NUMS}"
            ;;
        *)
            ;;
    esac
    echo ""

    echo "3. Display Settings"
    echo "-------------------"
    shared_prompt_text_default RESOLUTION "Display resolution" "${RESOLUTION}"
    shared_prompt_text_default DPI "DPI" "${DPI}"
    shared_prompt_text_default STREAM_SCALE "Stream resolution scale (0.25-1.0)" "${STREAM_SCALE}"
    shared_prompt_text_default FRAMERATE "Framerate (single value or range)" "${FRAMERATE}"
    echo ""

    echo "4. Language/Timezone Settings"
    echo "-----------------------------"
    echo "Select language (affects timezone):"
    echo "  ja) Japanese (Asia/Tokyo)"
    echo "  en) English (UTC)"
    shared_prompt_text_default lang_choice "Select language [ja/en]" "${default_lang_choice}"
    case "$(shared_to_lower "${lang_choice}")" in
        ja|jp)
            shared_apply_locale_from_timezone "Asia/Tokyo"
            echo "Japanese selected. Timezone: ${TIMEZONE}"
            ;;
        *)
            shared_apply_locale_from_timezone "UTC"
            echo "English selected. Timezone: ${TIMEZONE}"
            ;;
    esac
    echo ""

    echo "5. SSL Configuration (Optional)"
    echo "-------------------------------"
    if [[ -n "${SSL_DIR}" ]]; then
        shared_prompt_text_default SSL_DIR "SSL directory path (leave empty to skip)" "${SSL_DIR}"
    else
        shared_prompt_optional_text SSL_DIR "SSL directory path (leave empty to skip)"
    fi
    if [[ -z "${SSL_DIR}" ]]; then
        local default_ssl_dir
        default_ssl_dir="$(pwd)/ssl"
        if [[ -d "${default_ssl_dir}" ]]; then
            SSL_DIR="${default_ssl_dir}"
            echo "Using SSL dir: ${SSL_DIR}"
        fi
    fi
    echo ""

    echo "6. Mac / Docker Desktop Settings"
    echo "--------------------------------"
    if [[ "${HOST_IS_MAC:-false}" == "true" ]]; then
        echo "macOS (Darwin) detected."
        echo "Mac-specific settings apply."
        if shared_prompt_yes_no_default "Enable Mac-specific settings?" "${default_mac_choice}"; then
            IS_MAC="true"
            echo "Mac-specific settings enabled."
        else
            IS_MAC="false"
            echo "Mac-specific settings disabled."
        fi
    else
        echo "Non-macOS host detected ($(uname -s))."
        if shared_prompt_yes_no_default "Enable Mac / Docker Desktop-specific settings anyway?" "${default_mac_choice}"; then
            IS_MAC="true"
            echo "Mac-specific settings enabled."
        else
            IS_MAC="false"
            echo "Mac-specific settings disabled."
        fi
    fi
    echo ""
}
