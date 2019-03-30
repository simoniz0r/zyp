#!/bin/bash
# Author: simonizor
# License: MIT
# Dependencies: zypper, curl, xmlstarlet
# Description: A wrapper for 'zypper' that allows for easily
# installing packages from OBS repos and adds other functionality.

# exit if ran as root
if [[ $EUID -eq 0 ]]; then
    echo "Do not run 'zyp' as root!"
    exit 1
fi
# check if zyp cache dir exists
if [[ ! -d "$HOME/.cache/zyp" ]]; then
    mkdir -p "$HOME"/.cache/zyp
fi
# get colors from zypper.conf
colorparse() {
    case "$1" in
        red) echo "1";;
        green) echo "2";;
        blue) echo "4";;
        brown) echo "3";;
        cyan) echo "14";;
        purple|magenta) echo "5";;
        black) echo "0";;
        yellow) echo "11";;
        *) echo "7";;
    esac
}
if [[ -f "/etc/zypp/zypper.conf" ]]; then
    USE_COLORS="$(cat /etc/zypp/zypper.conf | grep -m1 'useColors' | cut -f2 -d'=' | tr -d '[:blank:]')"
    if [[ "$1" == "--no-color" ]]; then
        shift
        COLOR_INFO="7"
        COLOR_ERROR="7"
        COLOR_WARNING="7"
        COLOR_POSITIVE="7"
        COLOR_NEGATIVE="7"
    elif [[ "$USE_COLORS" != "never" ]]; then
        COLOR_INFO="$(colorparse $(cat /etc/zypp/zypper.conf | grep -m1 'highlight =' | cut -f2 -d'=' | tr -d '[:blank:]'))"
        COLOR_ERROR="$(colorparse $(cat /etc/zypp/zypper.conf | grep -m1 'msgError' | cut -f2 -d'=' | tr -d '[:blank:]'))"
        COLOR_WARNING="$(colorparse $(cat /etc/zypp/zypper.conf | grep -m1 'msgWarning' | cut -f2 -d'=' | tr -d '[:blank:]'))"
        COLOR_POSITIVE="$(colorparse $(cat /etc/zypp/zypper.conf | grep -m1 'positive =' | cut -f2 -d'=' | tr -d '[:blank:]'))"
        COLOR_NEGATIVE="$(colorparse $(cat /etc/zypp/zypper.conf | grep -m1 'negative =' | cut -f2 -d'=' | tr -d '[:blank:]'))"
    else
        COLOR_INFO="7"
        COLOR_ERROR="7"
        COLOR_WARNING="7"
        COLOR_POSITIVE="7"
        COLOR_NEGATIVE="7"
    fi
else
    COLOR_INFO="2"
    COLOR_ERROR="1"
    COLOR_WARNING="3"
    COLOR_POSITIVE="4"
    COLOR_NEGATIVE="1"
fi
# detect which version of openSUSE we're running
PRODUCT_SUMMARY="$(xmlstarlet sel -t -v '/product/summary' /etc/products.d/baseproduct | tr ' ' '_')"
if [[ -z "$PRODUCT_SUMMARY" ]]; then
    echo "$(tput setaf $COLOR_NEGATIVE)Error getting openSUSE summary from '/etc/products.d/baseproduct'; exiting...$(tput sgr0)"
    exit 0
fi
if [[ "$PRODUCT_SUMMARY" == "openSUSE_Tumbleweed" ]]; then
    OPENSUSE_VERSION="$PRODUCT_SUMMARY\|openSUSE_Factory"
else
    OPENSUSE_VERSION="$PRODUCT_SUMMARY"
fi
# get api username and password from https://raw.githubusercontent.com/simoniz0r/zyp/master/zyp.conf
obsauth() {
    curl -sL "https://raw.githubusercontent.com/simoniz0r/zyp/master/zyp.conf" -o "$HOME"/.cache/zyp/zyp.conf
    source "$HOME"/.cache/zyp/zyp.conf
    export OBS_USERNAME OBS_PASSWORD
    rm -f "$HOME"/.cache/zyp/zyp.conf
}
# function to output zypper's search results in a cleaner manner
zyppersearch() {
    zypper --no-refresh -x se "$@" | xmlstarlet sel -t -m "/stream/search-result/solvable-list/solvable" -v "concat(@name,'|',@status,'|',@kind,'|',@summary)" -n | tr ' ' '#' > "$HOME"/.cache/zyp/zypsearch.txt
    if [[ $(cat "$HOME"/.cache/zyp/zypsearch.txt | wc -l) -eq 0 ]]; then
        echo "No matching items found."
        ZYPPER_EXIT=104
    else
        for result in $(cat "$HOME"/.cache/zyp/zypsearch.txt); do
            echo "$(tput setaf $COLOR_INFO)"$(echo "$result" | cut -f1 -d'|')"$(tput sgr0) "\($(echo "$result" | cut -f3 -d'|')\)" "\[$(echo "$result" | cut -f2 -d'|')\]""
            echo -e "    "$(echo "$result" | cut -f4 -d'|' | tr '#' ' ')"\n"
            # echo "Status:  "$(echo "$result" | cut -f2 -d'|')""
            # echo "Type:    "$(echo "$result" | cut -f3 -d'|')""
            # echo "Summary: "$(echo "$result" | cut -f4 -d'|' | tr '#' ' ')""
        done > "$HOME"/.cache/zyp/zypresults.txt
        cat "$HOME"/.cache/zyp/zypresults.txt
        rm -f "$HOME"/.cache/zyp/zypresults.txt
        ZYPPER_EXIT=0
    fi
    rm -f "$HOME"/.cache/zyp/zypsearch.txt
}
# function to search for packages using the openSUSE Build Service API
searchobs() {
    case "$1" in
        --NOPRETTY) shift; local PRETTY_PRINT="FALSE";;
        *) local PRETTY_PRINT="TRUE";;
    esac
    if [[ "$MATCH_TEXT" == "TRUE" ]]; then
        curl -sL -u "$OBS_USERNAME:$OBS_PASSWORD" "https://api.opensuse.org/search/published/binary/id?match=%40name%3D%27$1%27" > "$HOME"/.cache/zyp/zypsearch.xml
        xmlstarlet sel -t -m "/collection/binary[@name='$1']" -v "concat(@name,'|',@version,'|',@project,'|',@repository,'|',@arch,'-arch','|',@package,'|',@filename)" -n "$HOME"/.cache/zyp/zypsearch.xml \
        | grep -v 'src-arch' | grep "$OPENSUSE_VERSION" | grep "noarch\|$(uname -m)" > "$HOME"/.cache/zyp/zypsearch.txt
    else
        curl -sL -u "$OBS_USERNAME:$OBS_PASSWORD" "https://api.opensuse.org/search/published/binary/id?match=contains%28%40name%2C+%27$1%27%29" > "$HOME"/.cache/zyp/zypsearch.xml
        xmlstarlet sel -t -m "/collection/binary" -v "concat(@name,'|',@version,'|',@project,'|',@repository,'|',@arch,'-arch','|',@package,'|',@filename)" -n "$HOME"/.cache/zyp/zypsearch.xml \
        | grep -v 'src-arch' | grep "$OPENSUSE_VERSION" | grep "noarch\|$(uname -m)" > "$HOME"/.cache/zyp/zypsearch.txt
    fi
    rm -f "$HOME"/.cache/zyp/zypsearch.xml
    if [[ "$PRETTY_PRINT" == "TRUE" ]]; then
        if [[ $(cat "$HOME"/.cache/zyp/zypsearch.txt | wc -l) -eq 0 ]]; then
            echo "No matching items found."
            rm -f "$HOME"/.cache/zyp/zypsearch.txt
            exit 104
        fi
        for result in $(cat "$HOME"/.cache/zyp/zypsearch.txt); do
            if [[ $(cat "$HOME"/.cache/zyp/zypsearch.txt | wc -l) -lt 6 ]]; then
                META_DESC="$(curl -sL -u "$OBS_USERNAME:$OBS_PASSWORD" "https://api.opensuse.org/published/$(echo "$result" | cut -f3 -d'|')/$(echo "$result" | cut -f4 -d'|')/$(echo "$result" | cut -f5 -d'|' | cut -f1 -d'-')/$(echo "$result" | cut -f1 -d'|')?view=ymp" | head -n -1 | tail -n +2 | xmlstarlet sel -t -v "/group/software/item/description" -n | tr '\n' ' ' | tr -d '*')"
            fi
            echo "$(tput setaf $COLOR_INFO)"$(echo "$result" | cut -f1 -d'|')"$(tput sgr0)/"$(echo "$result" | cut -f3 -d'|')" "$(echo "$result" | cut -f4 -d'|')" "$(echo "$result" | cut -f2 -d'|')""
            # echo "Version: "$(echo "$result" | cut -f2 -d'|')""
            # echo "Project: "$(echo "$result" | cut -f3 -d'|')""
            # echo "Repo:    "$(echo "$result" | cut -f4 -d'|')""
            if [[ ! -z "$META_DESC" ]]; then
                if [[ $(echo "$META_DESC" | wc -m) -lt 101 ]]; then
                    echo "    $META_DESC"
                else
                    echo "    "$(echo "$META_DESC" | cut -c-100)"..."
                fi
            fi
            echo
        done > "$HOME"/.cache/zyp/zypresults.txt
        cat "$HOME"/.cache/zyp/zypresults.txt
        rm -f "$HOME"/.cache/zyp/zypresults.txt
    fi
}
# function to get info about OBS packages
infoobs() {
    # if no results, exit
    if [[ $(cat "$HOME"/.cache/zyp/zypsearch.txt | wc -l) -eq 0 ]]; then
        echo "$(tput setaf $COLOR_NEGATIVE)Package '$PACKAGE' not found.$(tput sgr0)"
        exit 0
    fi
    # get the first result from searchobs
    local RESULT="$(cat "$HOME"/.cache/zyp/zypsearch.txt | head -n 1)"
    # get package info from OBS API
    curl -sL -u "$OBS_USERNAME:$OBS_PASSWORD" "https://api.opensuse.org/build/$(echo "$RESULT" | cut -f3 -d'|')/$(echo "$RESULT" | cut -f4 -d'|')/$(uname -m)/$(echo "$RESULT" | cut -f6 -d'|')/$(echo "$RESULT" | cut -f7 -d'|')?view=fileinfo" > "$HOME"/.cache/zyp/fileinfo.xml
    TEXT="Information-for-package-$(echo "$RESULT" | cut -f1 -d'|')"
    echo "Information for package $(echo "$RESULT" | cut -f1 -d'|')"
    # echo as many dashes as letters in above output text
    for word in $(echo "$TEXT" | sed -e 's/\(.\)/\1\n/g'); do
        echo -n "-"
    done
    echo
    # output info about package
    echo "Repository   $(tput setaf $COLOR_INFO):$(tput sgr0) $(echo "$RESULT" | cut -f4 -d'|')"
    echo "Name         $(tput setaf $COLOR_INFO):$(tput sgr0) $(echo "$RESULT" | cut -f1 -d'|')"
    echo "Version      $(tput setaf $COLOR_INFO):$(tput sgr0) $(echo "$RESULT" | cut -f2 -d'|')-$(xmlstarlet sel -t -v "/fileinfo/release" "$HOME"/.cache/zyp/fileinfo.xml)"
    echo "Vendor       $(tput setaf $COLOR_INFO):$(tput sgr0) obs://build.opensuse.org/$(echo "$RESULT" | cut -f3 -d'|')"
    echo "Package Size $(tput setaf $COLOR_INFO):$(tput sgr0) $(awk "BEGIN {print $(xmlstarlet sel -t -v "/fileinfo/size" "$HOME"/.cache/zyp/fileinfo.xml)/1024/1024}" | cut -c-5) MiB"
    echo "Installed    $(tput setaf $COLOR_INFO):$(tput sgr0) No"
    echo "Status       $(tput setaf $COLOR_INFO):$(tput sgr0) not installed"
    echo "Summary      $(tput setaf $COLOR_INFO):$(tput sgr0) $(xmlstarlet sel -t -v "/fileinfo/summary" "$HOME"/.cache/zyp/fileinfo.xml)"
    echo "Description  $(tput setaf $COLOR_INFO):$(tput sgr0)"
    echo "    $(tput setaf $COLOR_INFO)$(xmlstarlet sel -t -v "/fileinfo/description" "$HOME"/.cache/zyp/fileinfo.xml)$(tput sgr0)"
    # if --provides was used, output provides
    if [[ "$PROVIDES" == "TRUE" ]]; then
        if [[ $(xmlstarlet sel -t -v "/fileinfo/provides" "$HOME"/.cache/zyp/fileinfo.xml | wc -l) -gt 1 ]]; then
            echo "Provides     $(tput setaf $COLOR_INFO):$(tput sgr0) [$(xmlstarlet sel -t -v "/fileinfo/provides" "$HOME"/.cache/zyp/fileinfo.xml | wc -l)]"
            for prov in $(xmlstarlet sel -t -v "/fileinfo/provides" "$HOME"/.cache/zyp/fileinfo.xml | tr ' ' '#'); do
                echo "    $(tput setaf $COLOR_INFO)$prov$(tput sgr0)" | tr '#' ' '
            done
        else
            echo "Provides     $(tput setaf $COLOR_INFO):$(tput sgr0) $(xmlstarlet sel -t -v "/fileinfo/provides" "$HOME"/.cache/zyp/fileinfo.xml)"
        fi
    fi
    # if --requires was used, output requires
    if [[ "$REQUIRES" == "TRUE" ]]; then
        if [[ $(xmlstarlet sel -t -v "/fileinfo/requires" "$HOME"/.cache/zyp/fileinfo.xml | wc -l) -gt 1 ]]; then
            echo "Requires    $(tput setaf $COLOR_INFO):$(tput sgr0) [$(xmlstarlet sel -t -v "/fileinfo/requires" "$HOME"/.cache/zyp/fileinfo.xml | wc -l)]"
            for req in $(xmlstarlet sel -t -v "/fileinfo/requires" "$HOME"/.cache/zyp/fileinfo.xml | tr ' ' '#'); do
                echo "    $(tput setaf $COLOR_INFO)$req$(tput sgr0)" | tr '#' ' '
            done
        else
            echo "Requires     $(tput setaf $COLOR_INFO):$(tput sgr0) $(xmlstarlet sel -t -v "/fileinfo/requires" "$HOME"/.cache/zyp/fileinfo.xml)"
        fi
    fi
    # if --conflicts was used, output conflicts
    if [[ "$CONFLICTS" == "TRUE" ]]; then
        if [[ $(xmlstarlet sel -t -v "/fileinfo/conflicts" "$HOME"/.cache/zyp/fileinfo.xml | wc -l) -gt 1 ]]; then
            echo "Conflicts    $(tput setaf $COLOR_INFO):$(tput sgr0) [$(xmlstarlet sel -t -v "/fileinfo/conflicts" "$HOME"/.cache/zyp/fileinfo.xml | wc -l)]"
            for conf in $(xmlstarlet sel -t -v "/fileinfo/conflicts" "$HOME"/.cache/zyp/fileinfo.xml | tr ' ' '#'); do
                echo "    $(tput setaf $COLOR_INFO)$conf$(tput sgr0)" | tr '#' ' '
            done
        else
            echo "Conflicts    $(tput setaf $COLOR_INFO):$(tput sgr0) $(xmlstarlet sel -t -v "/fileinfo/conflicts" "$HOME"/.cache/zyp/fileinfo.xml)"
        fi
    fi
    # of --obsoletes was used, output obsoletes
    if [[ "$OBSOLETES" == "TRUE" ]]; then
        if [[ $(xmlstarlet sel -t -v "/fileinfo/obsoletes" "$HOME"/.cache/zyp/fileinfo.xml | wc -l) -gt 1 ]]; then
            echo "Obsoletes    $(tput setaf $COLOR_INFO):$(tput sgr0) [$(xmlstarlet sel -t -v "/fileinfo/obsoletes" "$HOME"/.cache/zyp/fileinfo.xml | wc -l)]"
            for obso in $(xmlstarlet sel -t -v "/fileinfo/obsoletes" "$HOME"/.cache/zyp/fileinfo.xml | tr ' ' '#'); do
                echo "    $(tput setaf $COLOR_INFO)$obso$(tput sgr0)" | tr '#' ' '
            done
        else
            echo "Obsoletes    $(tput setaf $COLOR_INFO):$(tput sgr0) $(xmlstarlet sel -t -v "/fileinfo/obsoletes" "$HOME"/.cache/zyp/fileinfo.xml)"
        fi
    fi
    # if --recommends was used, output recommends
    if [[ "$RECOMMENDS" == "TRUE" ]]; then
        if [[ $(xmlstarlet sel -t -v "/fileinfo/recommends" "$HOME"/.cache/zyp/fileinfo.xml | wc -l) -gt 1 ]]; then
            echo "Recommends   $(tput setaf $COLOR_INFO):$(tput sgr0) [$(xmlstarlet sel -t -v "/fileinfo/recommends" "$HOME"/.cache/zyp/fileinfo.xml | wc -l)]"
            for rec in $(xmlstarlet sel -t -v "/fileinfo/recommends" "$HOME"/.cache/zyp/fileinfo.xml | tr ' ' '#'); do
                echo "    $(tput setaf $COLOR_INFO)$rec$(tput sgr0)" | tr '#' ' '
            done
        else
            echo "Recommends   $(tput setaf $COLOR_INFO):$(tput sgr0) $(xmlstarlet sel -t -v "/fileinfo/recommends" "$HOME"/.cache/zyp/fileinfo.xml)"
        fi
    fi
    # if --suggests was used, output suggests
    if [[ "$SUGGESTS" == "TRUE" ]]; then
        if [[ $(xmlstarlet sel -t -v "/fileinfo/suggests" "$HOME"/.cache/zyp/fileinfo.xml | wc -l) -gt 1 ]]; then
            echo "Suggests     $(tput setaf $COLOR_INFO):$(tput sgr0) [$(xmlstarlet sel -t -v "/fileinfo/suggests" "$HOME"/.cache/zyp/fileinfo.xml | wc -l)]"
            for sugg in $(xmlstarlet sel -t -v "/fileinfo/suggests" "$HOME"/.cache/zyp/fileinfo.xml | tr ' ' '#'); do
                echo "    $(tput setaf $COLOR_INFO)$sugg$(tput sgr0)" | tr '#' ' '
            done
        else
            echo "Suggests     $(tput setaf $COLOR_INFO):$(tput sgr0) $(xmlstarlet sel -t -v "/fileinfo/suggests" "$HOME"/.cache/zyp/fileinfo.xml)"
        fi
    fi
    # if --supplements was used, output supplements
    if [[ "$SUPPLEMENTS" == "TRUE" ]]; then
        if [[ $(xmlstarlet sel -t -v "/fileinfo/supplements" "$HOME"/.cache/zyp/fileinfo.xml | wc -l) -gt 1 ]]; then
            echo "Supplements  $(tput setaf $COLOR_INFO):$(tput sgr0) [$(xmlstarlet sel -t -v "/fileinfo/supplements" "$HOME"/.cache/zyp/fileinfo.xml | wc -l)]"
            for supp in $(xmlstarlet sel -t -v "/fileinfo/supplements" "$HOME"/.cache/zyp/fileinfo.xml | tr ' ' '#'); do
                echo "    $(tput setaf $COLOR_INFO)$supp$(tput sgr0)" | tr '#' ' '
            done
        else
            echo "Supplements   $(tput setaf $COLOR_INFO):$(tput sgr0) $(xmlstarlet sel -t -v "/fileinfo/supplements" "$HOME"/.cache/zyp/fileinfo.xml)"
        fi
    fi
    echo
}
# function to install packages from OBS repos
installobs() {
    # if no results, exit
    if [[ $(cat "$HOME"/.cache/zyp/zypsearch.txt | wc -l) -eq 0 ]]; then
        echo "$(tput setaf $COLOR_NEGATIVE)Package '$PACKAGE' not found.$(tput sgr0)"
        exit 0
    fi
    # check if package already installed and prompt to continue
    if rpm -qi "$PACKAGE" > /dev/null 2>&1; then
        read -p "$(tput bold)'$PACKAGE' is already installed.  Continue? [y/n] (y):$(tput sgr0)" INSTALL_ANSWER
        case "$INSTALL_ANSWER" in
            N*|n*) echo "$(tput setaf $COLOR_INFO)Nothing to do.$(tput sgr0)"; exit 0;;
            *) echo;;
        esac
    fi
    PS3="$(echo -e "\nSelection: ")"
    echo -e "Select a package to install or enter 'q' to exit: \n"
    select OBSPKG in $(cat "$HOME"/.cache/zyp/zypsearch.txt | cut -f-5 -d '|' | rev | cut -f2- -d'-' | rev); do
        if [[ -z "$OBSPKG" ]]; then
            break
        fi
        META_DESC="$(curl -sL -u "$OBS_USERNAME:$OBS_PASSWORD" "https://api.opensuse.org/published/$(echo "$OBSPKG" | cut -f3 -d'|')/$(echo "$OBSPKG" | cut -f4 -d'|')/$(echo "$OBSPKG" | cut -f5 -d'|' | cut -f1 -d'-')/$(echo "$OBSPKG" | cut -f1 -d'|')?view=ymp" | head -n -1 | tail -n +2 | xmlstarlet sel -t -v "/group/software/item/description" -n | tr '\n' ' ' | tr -d '*')"
        PKG_NAME="$(echo "$OBSPKG" | cut -f1 -d'|')"
        PKG_VERSION="$(echo "$OBSPKG" | cut -f2 -d'|')"
        PKG_PROJECT="$(echo "$OBSPKG" | cut -f3 -d'|')"
        PKG_REPO="$(echo "$OBSPKG" | cut -f4 -d'|')"
        echo -e "\n$(tput setaf $COLOR_INFO)Name:    $PKG_NAME$(tput sgr0)"
        echo "Version: $PKG_VERSION"
        echo "Project: $PKG_PROJECT"
        echo "Repo:    $PKG_REPO"
        if [[ ! -z "$META_DESC" ]]; then
            if [[ $(echo "$META_DESC" | wc -m) -lt 101 ]]; then
                echo "Summary: $META_DESC"
            else
                echo "Summary: "$(echo "$META_DESC" | cut -c-100)"..."
            fi
        fi
        break
    done
    if [[ -z "$OBSPKG" ]]; then
        echo "$(tput setaf $COLOR_INFO)Nothing to do.$(tput sgr0)"
        exit 0
    fi
    echo
    # ask if user wants to install selected package
    read -p "$(tput bold)Install this package? [y/n] (y):$(tput sgr0) " ASKINSTALL_ANSWER
    case "$ASKINSTALL_ANSWER" in
        N|n|No|no) echo "$(tput setaf $COLOR_INFO)Nothing to do.$(tput sgr0)"; exit 0;;
    esac
    REPO_URL="http://download.opensuse.org/repositories/$(echo "$PKG_PROJECT" | sed 's%:%:\/%g')/$(echo "$PKG_REPO" | sed 's%:%:\/%g')/"
    FULL_REPO_URL="https://download.opensuse.org/repositories/$PKG_PROJECT/$PKG_REPO/$PKG_PROJECT.repo"
    REPO_NAME="$(echo $PKG_PROJECT | tr ':' '_')"
    # detect if user already has repo added
    if zypper -x lr | xmlstarlet sel -t -v "/stream/repo-list/repo/url" -n | grep -qm1 "$REPO_URL"; then
        echo "$(tput setaf $COLOR_INFO)$REPO_URL is already in the list of repositories.$(tput sgr0)"
        SKIP_REPOREM="TRUE"
    # else add repo
    else
        SKIP_REPOREM="FALSE"
        echo "$(tput setaf $COLOR_INFO)Adding '$REPO_NAME' to list of repositories...$(tput sgr0)"
        sudo zypper ar -f -p 100 -n "$REPO_NAME/$PKG_REPO" "$FULL_REPO_URL"
        local ZYPPER_EXIT=$?
        case $ZYPPER_EXIT in
            # if repo added, do nothing
            0)
                sleep 0
                ;;
            # any exit status from zypper other than 0 means repo add failed
            *)
                exit $ZYPPER_EXIT
                ;;
        esac
    fi
    # refresh to make sure user is prompted to trust repo
    sudo zypper ref
    echo "$(tput setaf $COLOR_INFO)Installing '$PKG_NAME' from repo '$REPO_NAME'..."
    # install package from repo
    sudo zypper --no-refresh in --from "$REPO_NAME" "$PKG_NAME"
    local ZYPPER_EXIT=$?
    # ask user if repo should be kept in list if repo was not already in list
    if [[ "$SKIP_REPOREM" == "FALSE" ]]; then
        read -p "$(tput bold)Keep '$REPO_NAME' in the list of repositories? [y/n] (y):$(tput sgr0) " ASKREMOVE_ANSWER
        case "$ASKREMOVE_ANSWER" in
            # rempve repo if answer is no
            N|n|No|no)
                sudo zypper --no-refresh rr "$REPO_NAME"
                local ZYPPER_EXIT=$?
                ;;
        esac
    fi
    exit $ZYPPER_EXIT
}
# function to parse openSUSE mailing list rss feeds using xmstarlet
mailinglist() {
    # detect which list user wants
    case "$1" in
        "") local MAILINGLIST="opensuse-factory";;
        *) local MAILINGLIST="opensuse-$1";;
    esac
    curl -sL "https://lists.opensuse.org/$MAILINGLIST/mailinglist.rss" | xmlstarlet sel -t -m "/rss/channel/item" -o "$(tput setaf $COLOR_INFO)Title: " -v "title" -n -o "$(tput sgr0)Link: " -v "link" -n -o "Date: " -v "pubDate" -n -o "Description:" -v "description" -n -n
}
# zyp help output
zyphelp() {
printf '%s\n' "
  Arguments provided by zyp:

      changes, ch          Show changes file for specified package(s).  Package(s) must be installed.
      list-files, lf       List files provided by specified package(s).  Package(s) must be installed.
      local-install, lin   Install a package using only repositories in zypper's list.
      local-search, lse    Run a search using only repositories in zypper's list.
      mailing-list, ml     Show latest posts from specified mailing list.  Default list is 'opensuse-factory'.
                           Valid choices can be found here: https://lists.opensuse.org/
                           'rsstail' must be installed to use this argument.
      obs-install, oin     Skip trying to use zypper to install a package and install from OBS repos.
      obs-search, ose      Skip searching with zypper and search for packages in OBS repos.
      orphaned, or         Lists installed packages which no longer have a repository associated with them.
                           '--list or -l' may be used to list only the package names.
                           '--remove or -r' may be used to remove all orphaned packages (USE WITH CAUTION).
"
}

# case to detect arguments
# run zypper with --no-refresh whenever possible to speed things up
case "$1" in
    # search for packages
    se|search)
        case "$2" in
            # if $2 = --match-words, run zypper seach, set MATCH_TEXT to TRUE, and run OBS search
            --binary|-b)
                shift 2
                cnf "$@" 2>&1 | sed 's%sudo zypper install%zyp install%'
                ;;
            -x|--match-exact)
                shift
                echo -e "$(tput setaf $COLOR_POSITIVE)Local Repositories Search Results:$(tput sgr0)\n"
                zyppersearch "$@"
                shift
                MATCH_TEXT="TRUE"
                echo
                echo -e "$(tput setaf $COLOR_POSITIVE)openSUSE Build Service Search Results:$(tput sgr0)\n"
                obsauth
                searchobs "$@"
                ;;
            # if $2 = -O or --obs, only run OBS search
            -O|--obs)
                shift 2
                case "$1" in
                    # if $3 = --match-words, set MATCH_TEXT to TRUE
                    -x|--match-exact)
                        shift
                        MATCH_TEXT="TRUE"
                        echo -e "$(tput setaf $COLOR_POSITIVE)Searching the openSUSE Build Service for '$@'...$(tput sgr0)\n"
                        obsauth
                        searchobs "$@"
                        ;;
                    *)
                        MATCH_TEXT="FALSE"
                        echo -e "$(tput setaf $COLOR_POSITIVE)Searching the openSUSE Build Service for '$@'...$(tput sgr0)\n"
                        obsauth
                        searchobs "$@"
                        ;;
                esac
                ;;
            # anything starting with letters runs both searches
            [a-z]*|[A-Z]*)
                shift
                echo -e "$(tput setaf $COLOR_POSITIVE)Local Repositories Search Results:$(tput sgr0)\n"
                zyppersearch "$@"
                MATCH_TEXT="FALSE"
                echo -e "$(tput setaf $COLOR_POSITIVE)openSUSE Build Service Search Results:$(tput sgr0)\n"
                obsauth
                searchobs "$@"
                ;;
            # local repos search only
            -L|--local) shift 2; zyppersearch "$@"; exit $ZYPPER_EXIT;;
            # Any other arguments get passed directly to zypper
            *) shift; zyppersearch "$@"; exit $ZYPPER_EXIT;;
        esac
        ;;
    # shortcut to local search
    lse|local-search) shift; "$0" se -L "$@";;
    # shortcut to OBS search
    ose|obs-search) shift; "$0" se -O "$@";;
    # if $2 = -O or --obs, install from OBS, otherwise try to install with zypper first
    in|install)
        case "$2" in
            # if $2 = -O or --obs, only run OBS search
            -O|--obs)
                shift 2
                MATCH_TEXT="TRUE"
                PACKAGE="$1"
                echo -e "$(tput setaf $COLOR_POSITIVE)Searching the openSUSE Build Service for '$PACKAGE'...$(tput sgr0)\n"
                obsauth
                searchobs "--NOPRETTY" "$PACKAGE"
                installobs
                ;;
            # anything starting with letters runs both searches
            # if zypper fails, try to find package in OBS
            [a-z]*|[A-Z]*)
                sudo zypper "$@"
                ZYPPER_EXIT=$?
                case $ZYPPER_EXIT in
                    # if zypper exits 104, package wasn't found, so search with osc
                    104)
                        echo -e "\n$(tput setaf $COLOR_POSITIVE)Package not found in repo list; searching with openSUSE Build Service...$(tput sgr0)\n"
                        shift
                        MATCH_TEXT="TRUE"
                        PACKAGE="$1"
                        obsauth
                        searchobs "--NOPRETTY" "$PACKAGE"
                        installobs
                        ;;
                    *)
                        exit $ZYPPER_EXIT
                        ;;
                esac
                ;;
            # local repos search only
            -L|--local) shift 2; sudo zypper install "$@";;
            # Any other arguments get passed directly to zypper
            *) sudo zypper "$@";;
        esac
        ;;
    # shortcut to local install
    lin|local-install) shift; "$0" in -L "$@";;
    # shortcut to OBS install
    oin|obs-install) shift; "$0" in -O "$1";;
    # if zypper fails, try to find package in OBS
    if|info)
        # zypper exits with 0 here regardless of package found or not, so check output for 'not found.'
        # if not found, search API and get info about latest build
        if [[ "$(zypper --no-refresh --no-color -q "$@" | tail -n +3)" =~ "not found." ]]; then
            shift
            MATCH_TEXT="TRUE"
            unset SUPPLEMENTS SUGGESTS REQUIRES RECOMMENDS PROVIDES OBSOLETES CONFLICTS
            # detect argument input
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --supplements) shift; SUPPLEMENTS="TRUE";;
                    --suggests) shift; SUGGESTS="TRUE";;
                    --requires) shift; REQUIRES="TRUE";;
                    --recommends) shift; RECOMMENDS="TRUE";;
                    --provides) shift; PROVIDES="TRUE";;
                    --obsoletes) shift; OBSOLETES="TRUE";;
                    --conflicts) shift; CONFLICTS="TRUE";;
                    *) PACKAGE="$1"; shift;;
                esac
            done
            # search for package to find info needed for build info API call
            obsauth
            searchobs "--NOPRETTY" "$PACKAGE"
            # get info about package
            infoobs
        # if output doesn't contain 'not found.', run zypper with user's input piped to tail -n +5 to get rid of repo loading output
        else
            zypper --no-refresh "$@" | tail -n +5
        fi
        ;;
    # --no-refresh to save time
    rm|remove) sudo zypper --no-refresh "$@";;
    # list and remove orphaned packages
    or|orphaned)
        case "$2" in
            # list orphaned packages separated by spaces
            -l|--list) zypper --no-color --no-refresh -q pa --orphaned | tail -n +3 | cut -f3 -d'|' | tr -d ' ' | tr '\n' ' '; echo;;
            # prompt to remove all orphaned packages
            -r|--remove) sudo zypper --no-refresh rm -u $(zypper --no-color --no-refresh -q pa --orphaned | tail -n +3 | cut -f3 -d'|' | tr -d ' ' | tr '\n' ' ');;
            # list orphaned packages in similar fashion to search output
            *)
                zypper --no-color --no-refresh -q pa --orphaned | tail -n +3 > "$HOME"/.cache/zyp/zyporphaned.txt
                for package in $(cat "$HOME"/.cache/zyp/zyporphaned.txt | cut -f3 -d'|' | tr -d ' '); do
                    echo "$(tput setaf $COLOR_INFO)Name:    $(cat "$HOME"/.cache/zyp/zyporphaned.txt | grep -w "$package" | cut -f3 -d'|' | tr -d ' ')$(tput sgr0)"
                    echo "Status:  $(cat "$HOME"/.cache/zyp/zyporphaned.txt | grep -w "$package" | cut -f1 -d'|' | tr -d ' ')"
                    echo "Version: $(cat "$HOME"/.cache/zyp/zyporphaned.txt | grep -w "$package" | cut -f4 -d'|' | tr -d ' ')"
                    echo "Arch:    $(cat "$HOME"/.cache/zyp/zyporphaned.txt | grep -w "$package" | cut -f5 -d'|' | tr -d ' ')"
                    echo "Repo:    $(cat "$HOME"/.cache/zyp/zyporphaned.txt | grep -w "$package" | cut -f2 -d'|' | tr -d ' ')"
                done
                rm -f "$HOME"/.cache/zyp/zyporphaned.txt
                ;;
        esac
        ;;
    # --no-refresh to save time
    pa|packages) zypper --no-refresh "$@";;
    # use rpm to get changelog for installed packages
    ch|changes)
        shift
        rpm -q --changes "$@"
        ;;
    # use rpm to list files of installed packages
    lf|list-files)
        shift
        rpm -q --filesbypkg "$@"
        ;;
    # run zypper ps -s as root
    ps)
        sudo zypper ps -s
        ;;
    # use xmlstarlet to get feeds from mailing lists
    ml|mailing-list)
        shift
        mailinglist "$@"
        ;;
    # help output
    help|-h|--help|"")
        zypper "$@"
        if [[ -z "$2" ]]; then
            zyphelp
        fi
        ;;
    *)
        # try to run zypper without sudo first
        zypper "$@" 2> ~/.cache/zyp/zyperrors
        ZYPPER_EXIT=$?
        case $ZYPPER_EXIT in
            # if zypper exit code is 5, failed because of perms; re-run with sudo
            5)
                rm -f ~/.cache/zyp/zyperrors
                sudo zypper "$@"
                ;;
            # otherwise output errors and exit
            *)
                cat ~/.cache/zyp/zyperrors
                rm -f ~/.cache/zyp/zyperrors
                exit $ZYPPER_EXIT
                ;;
        esac
        ;;
esac

