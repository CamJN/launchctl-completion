#!/usr/local/bin/bash
# Bash completion support for launchctl

# TODO:
#  fix commands that run other comamands to handle completion like sudo does (grep FIXME)
#      https://github.com/scop/bash-completion/blob/main/completions/sudo#L17
#      https://stackoverflow.com/questions/29231639/bash-completion-from-another-completion
#  fix file path completion putting spaces after directories
#      check if cur is a file otherwise add -o nospace ?
#  find way to list: asids, xpc-tokens, xsc-names, port-names
#  package section/segment dumper and install if missing
#  list deps like fd, segment_dumper

# -X '!*.plist'

# complete plists files when pwd is one of /library/ ~/library or a launch* dir in those


log () {
    echo "$*" >> /tmp/debug.log
}

__launchctl_paths ()
{
    readarray -t raw_files < <(\ls -1d {~,}/Library/Launch*/*)
    printf '%s\n' "${raw_files[@]/#$HOME/\~}"
}

__launchctl_array_contains ()
{
    local -n array=$1
    local element=$2
    for el in "${array[@]}"; do
        if [ "$el" = "$element" ]; then
            return 0
        fi
    done
    return 1
}

__launchctl_list_segments_and_sections ()
{
    tr : ' ' <<< "$PATH" | 2>/dev/null xargs fd . --type x | xargs segment_dumper 2>/dev/null | sort -u
}

__launchctl_list_umasks ()
{
    # shellcheck disable=SC2155
    local inner="$(seq 0 7 | paste -sd , -)"
    eval echo "{$inner}{$inner}{$inner}"
}

__launchctl_list_pids ()
{
    command ps axo pid= | tr -d ' ' | sort
}

__launchctl_list_uids ()
{
    dscl . -list /Users UniqueID 2>/dev/null | cut -wf 2 | sort
}

__launchctl_list_asids ()
{
    # audit session identifiers...
    # ps -p $$ -o sess=
    echo
}

__launchctl_list_domains ()
{
    echo {system,user,login,gui,pid} | tr ' ' '\n'
}

__launchctl_list_domain_targets ()
{
    case "${1:0:1}" in
        s) echo system; return;;
        p) __launchctl_list_pids  | xargs -n1 printf 'pid/%d\n';   return;;
        g) __launchctl_list_uids  | xargs -n1 printf 'gui/%d\n';   return;;
        l) __launchctl_list_asids | xargs -n1 printf 'login/%d\n'; return;;
        u) __launchctl_list_uids  | xargs -n1 printf 'user/%d\n';  return;;
    esac
}

__launchctl_list_service_targets ()
{
    case $2 in
        started) __launchctl_list_started | xargs -n1 printf "${1%/}/%s\n" | grep -e "^$1/"; return;;
        stopped) __launchctl_list_stopped | xargs -n1 printf "${1%/}/%s\n" | grep -e "^$1/"; return;;
        all)     __launchctl_list_labels  | xargs -n1 printf "${1%/}/%s\n" | grep -e "^$1/"; return;;
    esac
}

__launchctl_list_labels ()
{
    launchctl list | tail -n +2 | cut -f3 | grep -vEe '0x[0-9a-fA-F]+\.(anonymous|mach_init)'
}

__launchctl_list_started ()
{
    launchctl list | tail -n +2 | awk '$1 != "-"' | cut -f3 | grep -vEe '0x[0-9a-fA-F]+\.(anonymous|mach_init)'
}

__launchctl_list_stopped ()
{
    launchctl list | tail -n +2 | awk '$1 == "-"' | cut -f3 | grep -vEe '0x[0-9a-fA-F]+\.(anonymous|mach_init)'
}

__launchctl_list_envvars ()
{
    printenv | cut -d= -f1 | sort -u
}


_launchctl2 ()
{
    compopt +o default
    COMPREPLY=()
    local cur="${COMP_WORDS[COMP_CWORD]}"

    # Subcommand list
    local subcommands=(asuser attach blame bootout bootstrap bsexec config debug disable enable error examine getenv help hostinfo kickstart kill limit list load managername managerpid manageruid plist print print-cache print-disabled procinfo reboot remove resolveport setenv start stop submit unload unsetenv variant version bootshell print-token dump-xsc dumpjpcategory dumpstate)

    if [[ ${COMP_CWORD} -eq 1 ]]; then
        compgen -V COMPREPLY -W "${subcommands[*]}" -- "${cur}"
        return
    fi

    log "${COMP_WORDS[1]} ${COMP_CWORD}"
    case "${COMP_WORDS[1]}" in
        asuser)
            # asuser UID command [args]
            if [[ ${COMP_CWORD} -eq 2 ]]; then
                local possibilities=("$(__launchctl_list_uids | paste -sd ' ' -)")
                compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            else
                # TODO FIXME
                compgen -V COMPREPLY -cf -- "${cur}"
            fi
            return
            ;;
        attach)
            # attach [-ksx] service-target
            local flag_possibilities=(-k -s -x)
            local possibilities=()

            for value in "${flag_possibilities[@]}"; do
                if ! __launchctl_array_contains COMP_WORDS "$value"; then
                    possibilities+=("$value")
                fi
            done

            if __launchctl_array_contains flag_possibilities "${cur}"; then
                possibilities+=("${cur}")
            fi

            if [ "${cur:0:1}" = '-' ]; then
                compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            elif [ -z "${cur}" ]; then
                possibilities=("$(__launchctl_list_domains | xargs -n1 printf '%s/\n' | paste -sd ' ' -)")
                compgen -o nospace -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            elif [[ "${cur}" != */*/* ]]; then
                possibilities=("$(__launchctl_list_domain_targets "${cur}" | paste -sd ' ' -)")
                compopt -o nospace #doesn't work if set in compgen here...
                compgen -o nospace -S / -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            else
                possibilities=("$(__launchctl_list_service_targets "${cur%/*}" started | paste -sd ' ' -)")
                compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            fi

            return
            ;;
        blame)
            # blame service-target
            local possibilities=()
            if [ -z "${cur}" ]; then
                possibilities=("$(__launchctl_list_domains | xargs -n1 printf '%s/\n' | paste -sd ' ' -)")
                compgen -o nospace -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            elif [[ "${cur}" != */*/* ]]; then
                possibilities=("$(__launchctl_list_domain_targets "${cur}" | paste -sd ' ' -)")
                compopt -o nospace #doesn't work if set in compgen here...
                compgen -o nospace -S / -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            else
                possibilities=("$(__launchctl_list_service_targets "${cur%/*}" started | paste -sd ' ' -)")
                compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            fi
            return
            ;;
        bootout)
            # bootout domain-target [service-path service-path2 ...] | service-target
            local possibilities=()
            if [[ ${COMP_CWORD} -eq 2 ]]; then
                if [ -z "${cur}" ]; then
                    possibilities=("$(__launchctl_list_domains | xargs -n1 printf '%s/\n' | paste -sd ' ' -)")
                    compgen -o nospace -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
                else
                    possibilities=("$(__launchctl_list_domain_targets "${cur}" | paste -sd ' ' -)")
                    compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
                fi
            else
                local prev="${COMP_WORDS[2]}"
                readarray -t files < <(__launchctl_paths)
                if [ -z "${cur}" ]; then
                    compopt -o nospace #doesn't work if set in compgen here...
                    compgen -o nospace -S / -V COMPREPLY_RAW -W "${files[*]/%Library*/Library} $prev" -- "${cur}"
                    COMPREPLY=("${COMPREPLY_RAW[@]/#$HOME/\~}")
                elif [ "${cur:0:1}" = '~' ] || [ "${cur:0:1}" = '/' ]; then
                    eval "exp_cur=$cur"
                    compgen -V COMPREPLY_RAW -W "${files[*]}" -- "${exp_cur}"
                    COMPREPLY=("${COMPREPLY_RAW[@]/#$HOME/\~}")
                elif [[ "${cur}" != "$prev/"* ]]; then
                    compopt -o nospace #doesn't work if set in compgen here...
                    compgen -o nospace -S / -V COMPREPLY -W "$prev" -- "${cur}"
                else
                    possibilities=("$(__launchctl_list_service_targets "${cur%/*}" started | paste -sd ' ' -)")
                    compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
                fi
            fi
            return
            ;;
        bootstrap)
            # bootstrap domain-target [service-path service-path2 ...] | service-target
            local possibilities=()
            if [[ ${COMP_CWORD} -eq 2 ]]; then
                if [ -z "${cur}" ]; then
                    possibilities=("$(__launchctl_list_domains | xargs -n1 printf '%s/\n' | paste -sd ' ' -)")
                    compgen -o nospace -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
                else
                    possibilities=("$(__launchctl_list_domain_targets "${cur}" | paste -sd ' ' -)")
                    compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
                fi
            else
                local prev="${COMP_WORDS[2]}"
                readarray -t files < <(__launchctl_paths)
                if [ -z "${cur}" ]; then
                    compopt -o nospace #doesn't work if set in compgen here...
                    compgen -o nospace -S / -V COMPREPLY_RAW -W "${files[*]/%Library*/Library} $prev" -- "${cur}"
                    COMPREPLY=("${COMPREPLY_RAW[@]/#$HOME/\~}")
                elif [ "${cur:0:1}" = '~' ] || [ "${cur:0:1}" = '/' ]; then
                    eval "exp_cur=$cur"
                    compgen -V COMPREPLY_RAW -W "${files[*]}" -- "${exp_cur}"
                    COMPREPLY=("${COMPREPLY_RAW[@]/#$HOME/\~}")
                elif [[ "${cur}" != "$prev/"* ]]; then
                    compopt -o nospace #doesn't work if set in compgen here...
                    compgen -o nospace -S / -V COMPREPLY -W "$prev" -- "${cur}"
                else
                    possibilities=("$(__launchctl_list_service_targets "${cur%/*}" stopped | paste -sd ' ' -)")
                    compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
                fi
            fi
            return
            ;;
        bsexec)
            # bsexec PID command [args]
            if [[ ${COMP_CWORD} -eq 2 ]]; then
                local possibilities=("$(__launchctl_list_pids | paste -sd ' ' -)")
                compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            else
                # TODO FIXME
                compgen -V COMPREPLY -cf -- "${cur}"
            fi
            return
            ;;
        config)
            # config system | user parameter value
            if [[ ${COMP_CWORD} -eq 2 ]]; then
                Compgen -V COMPREPLY -W "system user" -- "${cur}"
            elif [[ ${COMP_CWORD} -eq 3 ]]; then
                compgen -V COMPREPLY -W "umask path" -- "${cur}"
            else
                case "${COMP_WORDS[3]}" in
                    umask) compgen -V COMPREPLY -W "$(__launchctl_list_umasks)" -- "${cur}";;
                    path) compgen -o nospace -V COMPREPLY -f -- "${cur}";;
                esac
            fi
            return
            ;;
        debug)
            # debug service-target [--program <program path>] [--guard-malloc] [--malloc-stack-logging] [--debug-libraries] [--introspection-libraries] [--NSZombie] [--32] [--stdin] [--stdout] [--stderr] [--environment] [--] [argv0 argv1 argv2 ...]
            local flag_possibilities=(--program --guard-malloc --malloc-stack-logging --malloc-nano-allocator --start-suspended --debug-libraries --introspection-libraries --NSZombie --32 --stdin --stdout --stderr --environment --)
            if [[ ${COMP_CWORD} -eq 2 ]]; then
                local possibilities=()
                if [ -z "${cur}" ]; then
                    possibilities=("$(__launchctl_list_domains | paste -sd ' ' -)")
                    compgen -o nospace -S / -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
                elif [[ "${cur}" != */*/* ]]; then
                    possibilities=("$(__launchctl_list_domain_targets "${cur}" | paste -sd ' ' -)")
                    compopt -o nospace #doesn't work if set in compgen here...
                    compgen -o nospace -S / -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
                else
                    possibilities=("$(__launchctl_list_service_targets "${cur%/*}" all | paste -sd ' ' -)")
                    compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
                fi
            elif [[ ${COMP_CWORD} -eq 3 ]]; then
                compgen -V COMPREPLY -W "${flag_possibilities[*]}" -- "${cur}"
            elif [[ ${COMP_CWORD} -gt 3 ]]; then
                if __launchctl_array_contains COMP_WORDS --; then
                    # complete args for debug command
                    compgen -V COMPREPLY -cf -- "${cur}"
                else
                    case "${COMP_WORDS[COMP_CWORD-1]}" in
                        --program)
                            # TODO FIXME
                            compgen -V COMPREPLY -cf -- "${cur}"
                            return
                            ;;
                        --stdin|--stdout|--stderr)
                            compgen -V COMPREPLY -f -- "${cur}"
                            return
                            ;;
                        --environment)
                            # [VARIABLE0=value0 VARIABLE1=value1 ...]
                            # maybe lookup $cur in word list and add = with nospace...
                            return
                            ;;
                        --)
                            # should be unreachable...
                            compgen -V COMPREPLY -cf -- "${cur}"
                            return
                            ;;
                        *)
                            local possibilities=()
                            for value in "${flag_possibilities[@]}"; do
                                if ! __launchctl_array_contains COMP_WORDS "$value"; then
                                    possibilities+=("$value")
                                fi
                            done
                            if __launchctl_array_contains flag_possibilities "${cur}"; then
                                possibilities+=("${cur}")
                            fi
                            compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
                            return
                            ;;
                    esac
                fi
            fi
            return
            ;;
        disable)
            # disable service-target
            if [ -z "${cur}" ]; then
                local possibilities=("$(__launchctl_list_domains | paste -sd ' ' -)")
                compgen -o nospace -S / -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            elif [[ "${cur}" != */*/* ]]; then
                local possibilities=("$(__launchctl_list_domain_targets "${cur}" | paste -sd ' ' -)")
                compopt -o nospace #doesn't work if set in compgen here...
                compgen -o nospace -S / -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            else
                local possibilities=("$(__launchctl_list_service_targets "${cur%/*}" started | paste -sd ' ' -)")
                compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            fi
            return
            ;;
        enable)
            # enable service-target
            if [ -z "${cur}" ]; then
                local possibilities=("$(__launchctl_list_domains | paste -sd ' ' -)")
                compgen -o nospace -S / -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            elif [[ "${cur}" != */*/* ]]; then
                local possibilities=("$(__launchctl_list_domain_targets "${cur}" | paste -sd ' ' -)")
                compopt -o nospace #doesn't work if set in compgen here...
                compgen -o nospace -S / -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            else
                local possibilities=("$(__launchctl_list_service_targets "${cur%/*}" stopped | paste -sd ' ' -)")
                compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            fi
            return
            ;;
        error)
            # error [posix|mach|bootstrap] code
            local possibilities=()
            if [[ ${COMP_CWORD} -eq 2 ]]; then
                possibilities=(posix mach bootstrap)
            else
                case "${COMP_WORDS[2]}" in
                    bootstrap) possibilities=("$(seq 0 56) $(seq 1000 1003) $(seq 1100 1105) $(seq 1601 1607)");;
                    mach) possibilities=("$(seq 1 56)");;
                    posix) possibilities=("$(seq 0 164)");;
                esac
            fi
            compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            return
            ;;
        examine)
            # examine [tool arg0 arg1 @PID ...]
            # TODO FIXME
            compgen -V COMPREPLY -cf -W '@PID' -- "${cur}"
            return
            ;;
        getenv)
            # getenv key
            local possibilities=("$(__launchctl_list_envvars | paste -sd ' ' -)")
            compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            return
            ;;
        help)
            # help <subcommand>
            compgen -V COMPREPLY -W "${subcommands[*]}" -- "${cur}"
            return
            ;;
        hostinfo)
            # hostinfo
            return
            ;;
        kickstart)
            # kickstart [-k] [-p] <service-target>
            local flag_possibilities=(-k -p)
            local possibilities=()

            for value in "${flag_possibilities[@]}"; do
                if ! __launchctl_array_contains COMP_WORDS "$value"; then
                    possibilities+=("$value")
                fi
            done

            if __launchctl_array_contains flag_possibilities "${cur}"; then
                possibilities+=("${cur}")
            fi

            if [ "${cur:0:1}" = '-' ]; then
                compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            elif [ -z "${cur}" ]; then
                possibilities+=("$(__launchctl_list_domains | xargs -n1 printf '%s/\n' | paste -sd ' ' -)")
                compgen -o nospace -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            elif [[ "${cur}" != */*/* ]]; then
                possibilities=("$(__launchctl_list_domain_targets "${cur}" | paste -sd ' ' -)")
                compopt -o nospace #doesn't work if set in compgen here...
                compgen -o nospace -S / -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            else
                possibilities=("$(__launchctl_list_service_targets "${cur%/*}" started | paste -sd ' ' -)")
                compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            fi

            return
            ;;
        kill)
            # kill <signal-number|signal-name> <service-target>
            if [[ ${COMP_CWORD} -eq 2 ]]; then
                compgen -V COMPREPLY -A signal -W "$(seq 1 31)" -- "${cur}"
            else
                if [ -z "${cur}" ]; then
                    local possibilities=("$(__launchctl_list_domains | paste -sd ' ' -)")
                    compgen -o nospace -S / -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
                elif [[ "${cur}" != */*/* ]]; then
                    local possibilities=("$(__launchctl_list_domain_targets "${cur}" | paste -sd ' ' -)")
                    compopt -o nospace #doesn't work if set in compgen here...
                    compgen -o nospace -S / -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
                else
                    local possibilities=("$(__launchctl_list_service_targets "${cur%/*}" stopped | paste -sd ' ' -)")
                    compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
                fi
            fi

            return
            ;;
        limit)
            # limit [<limit-name> [<both-limits> | <soft-limit> <hard-limit>]
            if [[ ${COMP_CWORD} -eq 2 ]]; then
                local possibilities=("cpu filesize data stack core rss memlock maxproc maxfiles")
                compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            else
                compgen -V COMPREPLY -W "unlimited" -- "${cur}"
            fi
            return
            ;;
        list)
            # list [service-name]
            local possibilities=("$(__launchctl_list_labels | paste -sd ' ' -)")
            compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            return
            ;;
        load)
            # load [-wF] [-S sessiontype] [-D searchpath] <service-path, service-path2, ...>
            local flag_possibilities=(-w -F -S -D)
            local possibilities=()
            for value in "${flag_possibilities[@]}"; do
                if ! __launchctl_array_contains COMP_WORDS "$value"; then
                    possibilities+=("$value")
                fi
            done
            if __launchctl_array_contains flag_possibilities "${cur}"; then
                possibilities+=("${cur}")
            fi

            if [[ ${COMP_CWORD} -gt 2 ]]; then
                case "${COMP_WORDS[COMP_CWORD-1]}" in
                    -S) compgen -V COMPREPLY -W "Aqua Background LoginWindow StandardIO System" -- "${cur}"; return ;;
                    -D) compgen -V COMPREPLY -W "system local network user" -- "${cur}"; return ;;
                esac
            fi

            readarray -t files < <(__launchctl_paths)

            if [ -z "${cur}" ]; then
                compgen -V COMPREPLY_RAW -W "${files[*]/%Library*/Library} ${possibilities[*]}" -- "${cur}"
                COMPREPLY=("${COMPREPLY_RAW[@]/#$HOME/\~}")
            elif [ "${cur:0:1}" = '-' ]; then
                compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            elif [ "${cur:0:1}" = '~' ]; then
                    eval "exp_cur=$cur"
                    # shellcheck disable=SC2154
                    compgen -V COMPREPLY_RAW -W "${files[*]}" -- "${exp_cur}"
                    COMPREPLY=("${COMPREPLY_RAW[@]/#$HOME/\~}")
            else
                compgen -V COMPREPLY -W "${files[*]}" -- "${cur}"
            fi
            return
            ;;
        managername)
            # managername
            return
            ;;
        managerpid)
            # managerpid
            return
            ;;
        manageruid)
            # manageruid
            return
            ;;
        plist)
            # plist [segment,section] Mach-O
            if [[ ${COMP_CWORD} -eq 2 ]]; then
                local possibilities=("$(__launchctl_list_segments_and_sections | paste -sd ' ' -)")
                compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            else
                compgen -V COMPREPLY -f -- "${cur}"
            fi
            return
            ;;
        print)
            # launchctl print <domain-target> | <service-target>
            if [ -z "${cur}" ]; then
                local possibilities=("$(__launchctl_list_domains | paste -sd ' ' -)")
                compgen -o nospace -S / -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            elif [[ "${cur}" != */*/* ]]; then
                local possibilities=("$(__launchctl_list_domain_targets "${cur}" | paste -sd ' ' -)")
                compopt -o nospace #doesn't work if set in compgen here...
                compgen -o nospace -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
                if [ ${#COMPREPLY[@]} -lt 2 ]; then
                    COMPREPLY+=("${COMPREPLY[@]}/")
                fi
            else
                local possibilities=("$(__launchctl_list_service_targets "${cur%/*}" all | paste -sd ' ' -)")
                compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            fi
            return
            ;;
        print-cache)
            # print-cache
            return
            ;;
        print-disabled)
            # print-disabled domain-target
            if [ -z "${cur}" ]; then
                local possibilities=("$(__launchctl_list_domains | xargs -n1 printf '%s/\n' | paste -sd ' ' -)")
                compgen -o nospace -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            elif [[ "${cur}" != */*/* ]]; then
                local possibilities=("$(__launchctl_list_domain_targets "${cur}" | paste -sd ' ' -)")
                compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            fi
            return
            ;;
        procinfo)
            # procinfo pid
            local possibilities=("$(__launchctl_list_pids | paste -sd ' ' -)")
            compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            return
            ;;
        reboot)
            # reboot [system|halt|userspace|logout|apps] [-s]
            local possibilities=(system halt userspace logout apps)
            compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            return
            ;;
        remove)
            # remove label
            local possibilities=("$(__launchctl_list_labels | paste -sd ' ' -)")
            compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            return
            ;;
        resolveport)
            # resolveport owner-pid port-name
            local possibilities=("$(__launchctl_list_pids | paste -sd ' ' -)")
            compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            return
            ;;
        setenv)
            # setenv key value
            return
            ;;
        start)
            # start label
            local possibilities=("$(__launchctl_list_labels | paste -sd ' ' -)")
            compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            return
            ;;
        stop)
            # stop label
            local possibilities=("$(__launchctl_list_labels | paste -sd ' ' -)")
            compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            return
            ;;
        submit)
            # submit -l label [-p executable] [-o stdout-path] [-e stderr-path] -- command [arg0] [arg1] [...]
            local flag_possibilities=(-l -p -o -e)

            __launchctl_array_contains COMP_WORDS "--"
            local in_command=$?

            if __launchctl_array_contains COMP_WORDS "-l"; then
                flag_possibilities+=(--)
            fi

            local possibilities=()
            for value in "${flag_possibilities[@]}"; do
                if ! __launchctl_array_contains COMP_WORDS "$value"; then
                    possibilities+=("$value")
                fi
            done

            if __launchctl_array_contains flag_possibilities "${cur}"; then
                possibilities+=("${cur}")
            fi

            if [ $in_command -eq 0 ]; then
                # TODO FIXME
                compgen -V COMPREPLY -cf -- "${cur}"
            else
                case "${COMP_WORDS[COMP_CWORD-1]}" in
                    -p) compgen -V COMPREPLY -cf -- "${cur}"; return;; # TODO FIXME
                    -o) compgen -V COMPREPLY -f -- "${cur}"; return;;
                    -e) compgen -V COMPREPLY -f -- "${cur}"; return;;
                    -l) return;;
                    *) compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"; return;;
                esac
            fi
            return
            ;;
        unload)
            # unload [-wF] [-S sessiontype] [-D searchpath] paths ...
            local flag_possibilities=(-w -F -S -D)

            local possibilities=()
            for value in "${flag_possibilities[@]}"; do
                if ! __launchctl_array_contains COMP_WORDS "$value"; then
                    possibilities+=("$value")
                fi
            done
            if __launchctl_array_contains flag_possibilities "${cur}"; then
                possibilities+=("${cur}")
            fi
            case "${COMP_WORDS[COMP_CWORD-1]}" in
                -S) compgen -V COMPREPLY -W "Aqua Background LoginWindow StandardIO System" -- "${cur}"; return ;;
                -D) compgen -V COMPREPLY -W "system local network user" -- "${cur}"; return ;;
            esac
            readarray -t files < <(__launchctl_paths)

            if [ -z "${cur}" ]; then
                compgen -V COMPREPLY_RAW -W "${files[*]/%Library*/Library} ${possibilities[*]}" -- "${cur}"
                COMPREPLY=("${COMPREPLY_RAW[@]/#$HOME/\~}")
            elif [ "${cur:0:1}" = '-' ]; then
                compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            elif [ "${cur:0:1}" = '~' ]; then
                    eval "exp_cur=$cur"
                    # shellcheck disable=SC2154
                    compgen -V COMPREPLY_RAW -W "${files[*]}" -- "${exp_cur}"
                    COMPREPLY=("${COMPREPLY_RAW[@]/#$HOME/\~}")
            else
                compgen -V COMPREPLY -W "${files[*]}" -- "${cur}"
            fi
            return
            ;;
        unsetenv)
            # unsetenv key
            local possibilities=("$(__launchctl_list_envvars | paste -sd ' ' -)")
            compgen -V COMPREPLY -W "${possibilities[*]}" -- "${cur}"
            return
            ;;
        variant)
            # variant
            return
            ;;
        version)
            # version
            return
            ;;
        bootshell)
            # bootshell [continue]
            compgen -V COMPREPLY -W "continue" -- "${cur}"
            return
            ;;
        print-token)
            # print-token <xpc token>
            return
            ;;
        dump-xsc)
            # dump-xsc <name>
            return
            ;;
        dumpjpcategory)
            # dumpjpcategory
            return
            ;;
        dumpstate)
            # dumpstate
            return
            ;;
    esac
}

complete -F _launchctl2 launchctl
