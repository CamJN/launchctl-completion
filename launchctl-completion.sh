#!/bin/bash
#
# Bash completion support for launchctl
__launchctl_list_sigs ()
{
    echo {,SIG}{HUP,INT,QUIT,ILL,TRAP,ABRT,EMT,FPE,KILL,BUS,SEGV,SYS,PIPE,ALRM,TERM,URG,STOP,TSTP,CONT,CHLD,TTIN,TTOU,IO,XCPU,XFSZ,VTALRM,PROF,WINCH,INFO,USR1,USR2} `seq 1 31 | tr '\n' ' '`
}

__launchctl_list_pids ()
{
    command ps axo pid=
}

__launchctl_list_uids ()
{
    dscl . -list /Users UniqueID 2>/dev/null | awk '{print $2}'
}

join_list ()
{
    tr -d ' ' | tr '\n' ',' | sed -e 's/.$//'
}

__launchctl_list_domains ()
{
    echo {system,user,gui,login,session,pid}/
}

__launchctl_list_subdomains ()
{
    pids=$(echo echo pid/{`__launchctl_list_pids | join_list`})
    pids=`eval $pids | tr ' ' ','`
    uids=$(echo echo {user,gui}/{`__launchctl_list_uids | join_list`})
    uids=`eval $uids | tr ' ' ','`
    #asids=  {login,session}/{asids...}
    eval $(echo echo {"system,${uids},${pids}"}/)
}

__launchctl_list_service_targets ()
{
    eval $(echo echo {`__launchctl_list_subdomains | tr ' ' ',' `}{`__launchctl_list_labels | join_list| tr ' ' ',' `})
}

__launchctl_list_labels ()
{
    launchctl list | awk 'NR>1 && $3 !~ /0x[0-9a-fA-F]+\.(anonymous|mach_init)/ {print $3}'
}

__launchctl_list_started ()
{
    launchctl list | awk 'NR>1 && $3 !~ /0x[0-9a-fA-F]+\.(anonymous|mach_init)/ && $1 !~ /-/ {print $3}'
}

__launchctl_list_stopped ()
{
    launchctl list | awk 'NR>1 && $3 !~ /0x[0-9a-fA-F]+\.(anonymous|mach_init)/ && $1 ~ /-/ {print $3}'
}

__launchctl_nospace() {
	# compopt is not available in ancient bash versions
	type compopt &>/dev/null && compopt -o nospace
}

_launchctl ()
{
    local cur prev two_prev

    COMPREPLY=()
    _get_comp_words_by_ref cur prev

    # Subcommand list
    local subcommands="bootstrap bootout enable disable uncache kickstart attach debug kill blame print print-cache print-disabledplist procinfo hostinfo resolveport limit runstats examine config dumpstate reboot bootshell load unload remove list start stop setenv unsetenv getenv bsexec asuser submit managerpid manageruid managername error variant version help"
    [[ ${COMP_CWORD} -eq 1 ]] && {
        COMPREPLY=( $(compgen -W "${subcommands}" -- ${cur}) )
        return
    }
    if [[ ${COMP_CWORD} -eq 2 ]]; then
        case "$prev" in
            print|enable|disable|blame|runstats|bootstrap|bootout|debug)
                __launchctl_nospace
                if [[ ${cur} == */*/* ]]; then
                    COMPREPLY=( $(compgen -W "$(__launchctl_list_service_targets)" -- ${cur}) )
                elif [[ ${cur} == */* ]]; then
                    COMPREPLY=( $(compgen -W "$(__launchctl_list_subdomains)" -- ${cur}) )
                else
                    COMPREPLY=( $(compgen -W "$(__launchctl_list_domains)" -- ${cur}) )
                fi
                return
                ;;
            submit)
                COMPREPLY=( $(compgen -W "-l" -- ${cur}) )
                return
                ;;
            help)
                COMPREPLY=( $(compgen -W "$subcommands" -- ${cur}) )
                return
                ;;
            kickstart)
                COMPREPLY=( $(compgen -W "-k -p -s" -- ${cur}) )
                return
                ;;
            reboot)
                COMPREPLY=( $(compgen -W "-s system halt userspace reroot logout apps" -- ${cur}) )
                return
                ;;
            attach)
                COMPREPLY=( $(compgen -W "-k -s -x" -- ${cur}) )
                return
                ;;
            bootshell)
                COMPREPLY=( $(compgen -W "continue" -- ${cur}) )
                return
                ;;
            procinfo|resolveport)
                COMPREPLY=( $(compgen -W '$(__launchctl_list_pids)' -- ${cur}) )
                return
                ;;
            error)
                COMPREPLY=( $(compgen -W "posix mach bootstrap" -- ${cur}) )
                return
                ;;
            remove|list|uncache)
                COMPREPLY=( $(compgen -W "$(__launchctl_list_labels)" -- ${cur}) )
                return
                ;;
            start)
                COMPREPLY=( $(compgen -W "$(__launchctl_list_stopped)" -- ${cur}) )
                return
                ;;
            stop)
                COMPREPLY=( $(compgen -W "$(__launchctl_list_started)" -- ${cur}) )
                return
                ;;
            kill)
                COMPREPLY=( $(compgen -W "$(__launchctl_list_sigs)" -- ${cur}) )
                return
                ;;
            bsexec)
                COMPREPLY=( $(compgen -W '$(__launchctl_list_pids)' -- ${cur}) )
                return
                ;;
            asuser)
                COMPREPLY=( $(compgen -W '$(__launchctl_list_uids)' -- ${cur}) )
                return
                ;;
            config)
                COMPREPLY=( $(compgen -W 'system user' -- ${cur}) )
                return
                ;;
            load|unload)
                _compopt_o_filenames
                __launchctl_nospace
                COMPREPLY=( $(compgen -f -- ${cur}) )
                return
                ;;
        esac
    fi
    if [[ ${COMP_CWORD} -eq 3 ]]; then
        two_prev="${COMP_WORDS[$COMP_CWORD-2]}"
        case "$two_prev" in
            config)
                COMPREPLY=( $(compgen -W "umask path" -- ${cur}) )
                return
                ;;
            reboot)
                COMPREPLY=( $(compgen -W "system halt userspace reroot logout apps" -- ${cur}) )
                return
                ;;
            kill|attach|kickstart)
                __launchctl_nospace
                if [[ ${cur} == */*/* ]]; then
                    COMPREPLY=( $(compgen -W "$(__launchctl_list_service_targets)" -- ${cur}) )
                elif [[ ${cur} == */* ]]; then
                    COMPREPLY=( $(compgen -W "$(__launchctl_list_subdomains)" -- ${cur}) )
                else
                    COMPREPLY=( $(compgen -W "$(__launchctl_list_domains)" -- ${cur}) )
                fi
                return
                ;;
            bootstrap|bootout)
                _compopt_o_filenames
                __launchctl_nospace
                COMPREPLY=( $(compgen -f -- ${cur}) )
                return
                ;;
            # resolveport)
            #     COMPREPLY=( $(compgen -W "$(__launchctl_list_ports)" -- ${cur}) )
            #     return
            #     ;;
        esac
    fi
}

complete -F _launchctl launchctl
