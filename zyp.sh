#!/bin/bash
# Author: simonizor
# License: MIT
# Dependencies: zypper, osc
# Description: A wrapper script for 'zypper' and 'osc' that adds install and search for openSUSE Build Sevice packages

# Function to ask questions.  Automatically detects number of options inputted.
# Detects if user inputs valid option and passes text of selected option on as SELECTED_OPTION variable
# Exits if invalid selection is made
function askquestion() {
    local QUESTION_TITLE="$1" 
    local QUESTION_TEXT="$2"
    shift 2
    local NUM_OPTIONS=$#
    local QUESTION_NUMBER=1
    echo "$(tput smul)$QUESTION_TITLE$(tput rmul)"
    echo
    echo -e "$QUESTION_TEXT"
    echo
    for option in $@; do
        [ $QUESTION_NUMBER -lt 10 ] && QUESTION_NUMBER=" $QUESTION_NUMBER"
        echo "${QUESTION_NUMBER}. $(echo $option | tr '%' ' ')"
        echo "$(echo $option | tr '%' ' ')" >> /tmp/questionoptions
        local QUESTION_NUMBER=$(($QUESTION_NUMBER+1))
    done
    echo
    read -p "Option number: " -r QUESTION_SELECTION
    [ -z "$QUESTION_SELECTION" ] && exit 0
    if echo "$QUESTION_SELECTION" | grep -q '^[0-9]' && [ $QUESTION_SELECTION -gt 0 ] && [ $QUESTION_SELECTION -le $NUM_OPTIONS ]; then
        export SELECTED_OPTION="$QUESTION_SELECTION"
        rm -f /tmp/questionoptions
        echo
    else
        rm -f /tmp/questionoptions
        exit 0
    fi
}

# function to search for packages
function searchpackages() {
    # get distro version from /etc/os-release and only search for packages for that distro
    . /etc/os-release
    local DISTRO="$(echo $NAME | cut -f2 -d' ')"
    case "$DISTRO" in
        *Tumbleweed*|*tumbleweed*)
            local SEARCH_RESULTS="$(osc bse --csv "$@" | tr '|' '\n' | grep "$(uname -m).rpm\|noarch.rpm" | grep -i "$DISTRO\|Factory")"
            ;;
        *)
            local SEARCH_RESULTS="$(osc bse --csv "$@" | tr '|' '\n' | grep "$(uname -m).rpm\|noarch.rpm" | grep -i "$DISTRO")"
            ;;
    esac
    [ ! -z "$SEARCH_RESULTS" ] && echo -e "$SEARCH_RESULTS" || echo "null"
}
# function that searches for packages
function searchstart() {
    case "$1" in
        # skip using repos in list
        -O|--osc|--obs|--OBS)
            shift
            sleep 0
            ;;
        # only send -s and package searches to osc; everything else goes to zypper and exits
        -s|[a-z]*|[A-Z]*|[0-9]*)
            $ZYPPER se "$@"
            local ZYPPER_EXIT=$?
            echo
            ;;
        *)
            [ "$1" = "-L" ] || [ "$1" = "--local" ] && shift
            $ZYPPER se "$@"
            exit 0
            ;;
    esac
    echo "openSUSE Build Service results:"
    echo
    # run searchpackages function and set it as SEARCH_RESULTS variable
    local SEARCH_RESULTS="$(searchpackages "$@")"
    case "$SEARCH_RESULTS" in
        null)
            echo "No matching items found."
            exit $ZYPPER_EXIT
            ;;
        *)
            LINE_LENGTH=0
            # for loop to detect length of project name to set spacing
            for line in $SEARCH_RESULTS; do
                NEW_LINE_LENGTH=$(echo $line | rev | cut -f4- -d'/' | rev | wc -m)
                [ $NEW_LINE_LENGTH -gt $LINE_LENGTH ] && LINE_LENGTH=$(($NEW_LINE_LENGTH+2))
            done
            printf "%-11s %-${LINE_LENGTH}s %-20s %s\n" "Version" "Project" "Repo" "Package"
            printf "%-11s %-${LINE_LENGTH}s %-20s %s\n" "-------" "-------" "----" "-------"
            # for loop that outputs results from osc in a sorted list
            for result in $SEARCH_RESULTS; do
                printf "%-12s %-${LINE_LENGTH}s %-20s %s\n" "|$(echo $result | rev | cut -f1 -d'/' | cut -f2 -d'-' | rev | cut -c-10)" \
                "$(echo $result | rev | cut -f4- -d'/' | rev)" \
                "$(echo $result | rev | cut -f3 -d'/' | rev | cut -f2- -d'_')" "$(echo $result | rev | cut -f1 -d'/' | cut -f3- -d'-' | rev)" >> /tmp/zypresults
            done
            echo "$(cat /tmp/zypresults | sort -fbdir -t\|)" > /tmp/zypresults
            cat /tmp/zypresults | cut -f2 -d'|'
            ;;
    esac
}
# function that displays a list of packages for install from OBS repos if none are available in repo list
function installstart() {
    case "$1" in
        # skip using repos in list
        -O|--osc|--obs|--OBS)
            shift
            case "$1" in
                -p|--priority)
                    shift
                    export REPO_PRIORITY=$1
                    shift
                    ;;
            esac
            sleep 0
            ;;
        # set priority for repo when adding
        -p|--priority)
            shift
            export REPO_PRIORITY=$1
            shift
            ;;
        *)
            sudo $ZYPPER in "$@" 
            ZYPPER_EXIT=$?
            case $ZYPPER_EXIT in
                # if zypper exits 104, package wasn't found, so search with osc
                104)
                    echo "Package not found in repo list; searching with osc..."
                    echo
                    ;;
                *)
                    exit $ZYPPER_EXIT
                    ;;
            esac
            ;;
    esac
    # set priority to 100 by default
    [ -z "$REPO_PRIORITY" ] && export REPO_PRIORITY=100
    # run searchpackages function and send results to /tmp/zypsearch
    searchpackages "$@" > /tmp/zypsearch 2>&1
    if [ ! "$(cat /tmp/zypsearch)" = "null" ]; then
        local START_NUM=11
        local LINE_LENGTH=0
        # for loop to detect length of project name to set spacing
        for line in $(cat /tmp/zypsearch); do
            NEW_LINE_LENGTH=$(echo $line | rev | cut -f4- -d'/' | rev | wc -m)
            [ $NEW_LINE_LENGTH -gt $LINE_LENGTH ] && LINE_LENGTH=$(($NEW_LINE_LENGTH+2))
        done
        # for loop that outputs results from osc in a sorted list to /tmp/zypresults
        for result in $(cat /tmp/zypsearch); do
            printf "%-14s %-${LINE_LENGTH}s %-20s %s\n" "$START_NUM|$(echo $result | rev | cut -f1 -d'/' | cut -f2 -d'-' | rev | cut -c-10)" \
            "$(echo $result | rev | cut -f4- -d'/' | rev)" \
            "$(echo $result | rev | cut -f3 -d'/' | rev | cut -f2- -d'_')" "$(echo $result | rev | cut -f1 -d'/' | cut -f3- -d'-' | rev)" >> /tmp/zypresults
            local START_NUM=$(($START_NUM+1))
        done
        # sort based on version number
        echo "$(cat /tmp/zypresults | sort -fbdir -t\| -k2 | tr ' ' '%')" > /tmp/zypresults
        # ask which package user wants to install
        askquestion "Select a package to install or press ENTER to exit:" "$(printf "%-14s %-${LINE_LENGTH}s %-20s %s\n" \
        " Version" " Project" " Repo" " Package")\n$(printf "%-14s %-${LINE_LENGTH}s %-20s %s\n" " -------" " -------" " ----" " -------")" \
        $(cat /tmp/zypresults | cut -f2 -d'|' | tr '\n' ' ')
        # get selected package based on number input from function above by using sed to select chosen row
        SELECTED_RESULT="$(sed "${SELECTED_OPTION}q;d" /tmp/zypresults | cut -f1 -d'|')"
        SELECTED_RESULT=$(($SELECTED_RESULT-10))
        SELECTED_PACKAGE="$(sed "${SELECTED_RESULT}q;d" /tmp/zypsearch)"
        [ -z "$SELECTED_PACKAGE" ] && exit 0
        # output description of package from osc ymp data
        echo "Selection:"
        echo -e "$SELECTED_PACKAGE\n"
        echo "Description:"
        local API_PACKAGE="$(echo $SELECTED_PACKAGE | sed 's%:/%:%g')"
        echo -e "$(osc api /published/$API_PACKAGE?view=ymp | tac | awk '/<\/metapackage/,/<\/repositories>/' | awk '/<\/description>/,/<description>/' | cut -f2 -d'>' | cut -f1 -d'<' | tac)\n"
        # ask if package should be installed and run addobsrepo function if anything other than no chosen
        read -p "$(tput bold)Add repository and install package? [y/n] (y):$(tput sgr0) " INSTALL_ANSWER
        echo
        case $INSTALL_ANSWER in
            N*|n*)
                exit 0
                ;;
            *)
                addobsrepo "$SELECTED_PACKAGE"
                ;;
        esac
    else
        echo "Package '$@' not found."
        exit 104
    fi
}
# function that checks if package is installed then checks if repo is in list
# if repo is not in list, repo is added with default priority of 100
function addobsrepo() {
    local PACKAGE="$(echo $1 | rev | cut -f1 -d'/' | cut -f2- -d'-' | rev)"
    local REPO_URL="http://download.opensuse.org/repositories/$(echo $1 | rev | cut -f3- -d'/' | rev)"
    local REPO_RELEASE="$(echo $1 | rev | cut -f3 -d'/' | rev | cut -f2 -d'_')"
    local PROJECT_NAME="$(echo $1 | rev | cut -f4- -d'/' | rev | tr -d '/')"
    local REPO_NAME="$(echo $1 | rev | cut -f4- -d'/' | rev | tr -d '/' |tr ':' '_')"
    if rpm -qa | grep -qm1 "$PACKAGE"; then
        echo "'$PACKAGE' is already installed."
        echo "Nothing to do."
        exit 0
    fi
    if zypper lr -U | grep -qm1 "$REPO_URL"; then
        echo "$REPO_URL is already in the list of repositories."
        SKIP_REPOREM="TRUE"
        installpackage "$SKIP_REPOREM" "$REPO_NAME" "$PACKAGE"
    else
        SKIP_REPOREM="FALSE"
        sudo $ZYPPER ar -f -p $REPO_PRIORITY -n "$REPO_NAME/$REPO_RELEASE" ${REPO_URL}/${PROJECT_NAME}.repo
        local ZYPPER_EXIT=$?
        case $ZYPPER_EXIT in
            0)
                installpackage "$SKIP_REPOREM" "$REPO_NAME" "$PACKAGE"
                ;;
            *)
                exit $ZYPPER_EXIT
                ;;
        esac
    fi
}
# function that installs package and then runs askremove function if SKIP_REPOREM=FALSE
function installpackage() {
    local SKIP_REPOREM="$1"
    local REPO_NAME="$2"
    local PACKAGE="$3"
    sudo $ZYPPER install "$PACKAGE"
    local ZYPPER_EXIT=$?
    case $ZYPPER_EXIT in
        0|4|104)
            [ "$SKIP_REPOREM" = "FALSE" ] && askremoverepo "$REPO_NAME" "$ZYPPER_EXIT"
            ;;
        *)
            exit $ZYPPER_EXIT
            ;;
    esac
}
# function that asks if repo should be removed after install if it wasn't already in list
function askremoverepo() {
    local REPO_NAME="$1"
    local ZYPPER_EXIT=$2
    read -p "$(tput bold)Keep '$REPO_NAME' in the list of repositories? [y/n] (y):$(tput sgr0) " ASKREMOVE_ANSWER
    case "$ASKREMOVE_ANSWER" in
        N*|n*)
            unset ZYPPER_EXIT
            sudo $ZYPPER rr "$REPO_NAME"
            local ZYPPER_EXIT=$?
            exit $ZYPPER_EXIT
            ;;
        *)
            exit $ZYPPER_EXIT
            ;;
    esac
}
# function to display zyp's help
function zyphelp() {
    printf '%s\n' "
     Subarguments provided by zyp:
         --obs, -O              Search for or install only packages from openSUSE Build Service repos.
         --local, -L            Search for or install only packages from repos already in list.
         --priority, -P         Set the priority for the repository when installing packages from OBS repos.
                                (default is 100)
    "
}
# function to handle argument input
function zypstart() {
    case "$1" in
        se|search)
            rm -f /tmp/zypsearch /tmp/zypresults
            shift
            searchstart "$@"
            rm -f /tmp/zypsearch /tmp/zypresults
            ;;
        in|install)
            rm -f /tmp/zypsearch /tmp/zypresults
            shift
            installstart "$@"
            rm -f /tmp/zypsearch /tmp/zypresults
            ;;
        ps)
            sudo $ZYPPER ps -s
            ;;
        help|-h|--help)
            $ZYPPER help
            zyphelp
            ;;
        *)
            if [ -z "$1" ]; then
                $ZYPPER help
                zyphelp
                exit 0
            fi
            $ZYPPER "$@" 2> /tmp/zyperrors
            local ZYPPER_EXIT=$?
            case $ZYPPER_EXIT in
                5)
                    rm -f /tmp/zyperrors
                    sudo $ZYPPER "$@"
                    ;;
                *)
                    cat /tmp/zyperrors
                    rm -f /tmp/zyperrors
                    exit $ZYPPER_EXIT
                    ;;
            esac
            ;;
    esac
}
# prevent script from running as root unless argument passed
if [ "$1" = "-S" ] || [ "$1" = "--skip-check" ]; then
    shift
elif [ $EUID -eq 0 ]; then
    echo "It is not recommended to run 'zyp' as root."
    echo "'zyp' will automatically escalate privileges when necessary."
    echo "Run 'zyp --skip-check' or 'zyp -S' to bypass this check."
    exit 1
fi
# check if user has logged into osc
if [ ! -d "$HOME/.config/osc" ] || [ ! -f "$HOME/.config/osc/oscrc" ]; then
    echo "Please run 'osc' and login before running 'zyp'"
    echo "If you do not have an account, create one here:"
    echo "https://secure-www.novell.com/selfreg/jsp/createOpenSuseAccount.jsp?%22"
    exit 1
fi
# enable quiet mode
case "$1" in
    -q|--quiet)
        shift
        ZYPPER="zypper -q"
        ;;
    *)
        ZYPPER="zypper"
        ;;
esac
zypstart "$@" && exit 0
