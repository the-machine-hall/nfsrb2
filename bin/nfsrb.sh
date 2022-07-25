#!/usr/bin/env sh

#set -x

# build NFS root file systems for OpenBSD and NetBSD ((pdk)sh version)
#
# should work on:
# * Linux with:
#   * dash as sh
#   * bash as sh (maybe)
# * OpenBSD with:
#   * pdksh as sh
# * NetBSD with
#   * posix shell as sh

:<<COPYRIGHT

Copyright (C) 2014-2022 Frank Scheiner

The program is distributed under the terms of the GNU General Public License

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

COPYRIGHT

################################################################################
# DEFINES
################################################################################

readonly _PROGRAM="nfsrb"

readonly _NFSRB_VERSION="2.0.0"
readonly _NFSRB_CONFIG_DIR="${HOME}/.nfsrb"
readonly _NFSRB_DEFAULT_ADD_FILES_TREE="${_NFSRB_CONFIG_DIR}/add-files"
readonly _NFSRB_DEFAULT_BASE_PATH_PREFIX="/srv/nfs"

readonly _EXIT_USAGE=64

readonly _TRUE=1
readonly _FALSE=0

########################################################################
# Configuration specific to OpenBSD file systems
########################################################################

# Prior to OpenBSD 5.7, the etc set is separate from the base set
_openbsd_defaultSets="base etc"

# Since OpenBSD 5.7, the etc set is included in the base set
_openbsd_defaultSetsSince57="base"

# Minimum OpenBSD version with signify support for downloads
_openbsd_signifySupportSince="55"

# Minimum OpenBSD version which was supplied with a hashfile
_openbsd_hashFileSince="46"

# Signature file name
_openbsd_signatureFileName="SHA256.sig"

# File containing the build date
_openbsd_buildinfoFileName="BUILDINFO"

# File containing the hashes
_openbsd_hashFileName="SHA256"

########################################################################

########################################################################
# Configuration specific to NetBSD file systems
########################################################################

_netbsd_defaultSets="base etc"

# File containing the hashes
_netbsd_hashFileName="SHA512"

__GLOBAL__cwd="$PWD"

########################################################################
# FUNCTIONS
########################################################################

########################################################################
# General functionality
########################################################################

usageMsg()
{
	cat 1>&2 <<-USAGE
		Usage: $_PROGRAM "configurationFile"
	USAGE

	return
}


downloadFile()
{
	local _file="$1"
	local _targetDir="$2"

	local _ftpReturned=1

	if [ -e "$_targetDir" ]; then

		cd "$_targetDir"
	else
		return 2
	fi

	if [ $( uname -s ) = "OpenBSD" ]; then

		ftp -C "$_file"
		_ftpReturned=$?

		if [ $_ftpReturned -eq 0 -o \
		     $_ftpReturned -eq 1 ]; then

			# ftp on OpenBSD exits with 1 if a file was already downloaded
			# completely. Hence let's assume 0 and 1 as sane exit value.
			true
		else
			false
		fi

	elif [ $( uname -s ) = "NetBSD" ]; then

		ftp "$_file"
		_ftpReturned=$?
		# TODO:
		# Implement error handling.

	elif [ $( uname -s ) = "Linux" ]; then

		# check if wget is available
		if which wget 1>/dev/null 2>&1; then

			if [ -e $( basename "$_file" ) ]; then

				wget -4 --progress=bar -c "$_file"

				if [ $? -eq 8 ]; then

					rm $( basename "$_file" )
					wget -4 --progress=bar "$_file"
				fi
			else
				wget -4 --progress=bar "$_file"
			fi

		elif which curl 1>/dev/null 2>&1; then

			# Actually curl should continue to download a partially downloaded file
			# with `-C -`, but during my tests it didn't. even when using `-o` and
			# the file name of the partially downloaded file.
			curl -O -C - "$_file"
		else
			# TODO:
			# Maybe change to log mesage?
			echo "Neither wget nor curl found." 1>&2
			return 1
		fi
	fi

	return
}


untarFile()
{
	local _tarFile="$1"
	local _logOfOperation="$2"

	local _tarCommand=""

	if [ $( uname -s ) = "OpenBSD" -o \
	     $( uname -s ) = "NetBSD" ]; then

		_tarCommand="tar -xpf $_tarFile"

	elif [ $( uname -s ) = "Linux" ]; then

		_tarCommand="tar --numeric-owner -xpf $_tarFile"
	fi

	echo "$_tarCommand" >"$_logOfOperation"
	$_tarCommand 1>>"$_logOfOperation" 2>&1

	if [ $? -eq 0 ]; then

		rm "$_logOfOperation"
		return 0
	else
		return 1
	fi
}


hashFile()
{
	local _file="$1"

	local _hash=""

	# TODO:
	# Check output of hash commands!

	if [ $( uname -s ) = "OpenBSD" ]; then

		_hash=$( sha256 -q "$_file" | cut -d ' ' -f 4 )

	elif [ $( uname -s ) = "NetBSD" ]; then

		_hash=$( cksum -a SHA256 "$_file" | cut -d ' ' -f 4 )

	elif [ $( uname -s ) = "Linux" ]; then

		_hash=$( sha256sum --tag "$_file" | cut -d ' ' -f 4 )
	fi

	if [ $? -eq 0 ]; then

		echo "$_hash"
		return 0
	else
		return 1
	fi
}


hashString()
{
	local _string="$1"

	local _hash=""

	# TODO:
	# Check output of hash commands!

	if [ $( uname -s ) = "OpenBSD" ]; then

		_hash=$( echo "$_string" | sha256 -q | cut -d ' ' -f 4 )

	elif [ $( uname -s ) = "NetBSD" ]; then

		_hash=$( echo "$_string" | cksum -a SHA256 | cut -d ' ' -f 4 )

	elif [ $( uname -s ) = "Linux" ]; then

		_hash=$( echo "$_string" | sha256sum --tag | cut -d ' ' -f 4 )
	fi

	if [ $? -eq 0 ]; then

		echo "$_hash"
		return 0
	else
		return 1
	fi
}


createSwapFile()
{
	local _swapFile="$1"
	local _logOfOperation="$2"

	if [ $( uname -s ) = "OpenBSD" -o \
	     $( uname -s ) = "Linux" ]; then

		_ddCommand="dd if=/dev/zero of="$_swapFile" bs=1M seek="$__SWAP_FILE_SIZE" count=0"

	# NetBSD uses "m" for Mebibyte and cannot create sparse files AFAICS
	elif [ $( uname -s ) = "NetBSD" ]; then

		_ddCommand="dd if=/dev/zero of="$_swapFile" bs=1m seek="$(( $__SWAP_FILE_SIZE - 1 ))" count=1"
	fi

	echo "$_ddCommand" >"$_logOfOperation"
	$_ddCommand 1>>"$_logOfOperation" 2>&1 && chmod 0600 "$_swapFile"

	return
}


log()
{
	local _logFile="$1"
	local _logLine="$2"

	# e.g                 2016-12-12 09:42:27 CET (1481532147)
	local _date="$( date "+%Y-%m-%d %T %Z (%s)" )"

	#/bin/echo -e -n "[$_date] $_logLine" >> "$_logFile"
	/bin/echo -e -n "$_logLine" >> "$_logFile"

	return
}


addFiles()
{
	local _rootPath="$1"
	local _logFile="$2"

	local _self="addFiles"

	if [ -d "${__ADD_FILES_TREE}" ]; then

		log "$_logFile" "[$_self] Now installing additional files...\n"

		if [ -d "${__ADD_FILES_TREE}/GENERIC" ]; then

			log "$_logFile" "[$_self] Installing generic files..."
			cp -radv "${__ADD_FILES_TREE}/GENERIC/"* "$_rootPath/" >> "$_logFile"
		fi

		if [ -d "${__ADD_FILES_TREE}/${__OS}/GENERIC" ]; then

			log "$_logFile" "[$_self] Installing OS specific files..."
			cp -radv "${__ADD_FILES_TREE}/${__OS}/GENERIC/"* "$_rootPath/" >> "$_logFile"
		fi

		if [ -d "${__ADD_FILES_TREE}/${__OS}/${__PLATFORM}/GENERIC" ]; then

			log "$_logFile" "[$_self] Installing OS specific files..."
			cp -radv "${__ADD_FILES_TREE}/${__OS}/${__PLATFORM}/GENERIC/"* "$_rootPath/" >> "$_logFile"
		fi

		if [ -d "${__ADD_FILES_TREE}/${__OS}/${__PLATFORM}/${__HOSTNAME}" ]; then

			log "$_logFile" "[$_self] Installing host specific files..."
			cp -radv "${__ADD_FILES_TREE}/${__OS}/${__PLATFORM}/${__HOSTNAME}/"* "$_rootPath/" >> "$_logFile"
		fi
	fi

	return
}


########################################################################
# Functionality specific to OpenBSD file systems
########################################################################

openbsd_getBuildDate()
{
	local _buildinfoFile="$1"

	local _buildDate=""

	_buildDate=$( head -1 "$_buildinfoFile" 2>/dev/null | cut -d ' ' -f 3 2>/dev/null )

	if [ $? -eq 0 ]; then

		echo $_buildDate
		return 0
	else
		return 1
	fi
}



openbsd_isValidFileForSignify()
{
	local _openBsdVersionNonDotted="$1"
	local _signatureFile="$2"
	local _file="$3"

	# TODO:
	# It needs to be checked, if signify can also work when _file contains the path and the file name

	if signify -C -p "/etc/signify/openbsd-${_openBsdVersionNonDotted}-base.pub" -x "$_signatureFile" "$_file" 1>/dev/null 2>&1; then

		return 0
	else
		return 1
	fi
}


openbsd_isValidFileForSha256()
{
	local _hashFile="$1"
	local _file="$2"

	local _fileName=$( basename "$_file" )

	local _tempHashFile=$( mktemp )
	local _validityCheckReturned=1

	grep "($_fileName)" "$_hashFile" > "$_tempHashFile"

	if [ $( uname -s ) = "OpenBSD" ]; then

		sha256 -c "$_tempHashFile" 1>/dev/null 2>&1

	elif [ $( uname -s ) = "NetBSD" ]; then

		cksum -c -a SHA256 "$_tempHashFile" 1>/dev/null 2>&1

	elif [ $( uname -s ) = "Linux" ]; then

		sha256sum -c "$_tempHashFile" 1>/dev/null 2>&1
	fi

	_validityCheckReturned=$?

	rm "$_tempHashFile"

	return $_validityCheckReturned
}


openbsd_getNonDottedVersionFromSignatureFile()
{
	local _signatureFile="$1"

	local _versionNonDotted
	local _version

	_versionNonDotted=$( grep '(base' < "$_signatureFile" | sed -e 's/^.* (//' -e 's/) .*$//' | sed -e 's/^base//' -e 's/.tgz//' )

	if [ $? -eq 0 ]; then

		echo $_versionNonDotted
		return 0
	else
		return 1
	fi
}


openbsd_nonDottedToDottedVersion()
{
	local _openBsdVersionNonDotted="$1"

	local _openBsdVersion=""

	local _length=${#_openBsdVersionNonDotted}

	_openBsdVersion=$( echo $_openBsdVersionNonDotted | cut -c 1-$(( _length - 1 )) ).$( echo $_openBsdVersionNonDotted | cut -c $_length)

	if [ $? -eq 0 ]; then

		echo $_openBsdVersion
		return 0
	else
		return 1
	fi
}


openbsd_getBasePath()
{
	local _downloadBasePath="$1"
	#local _basePathPrefix="$2"
	#local _openBsdVersion="$3"
	local _buildinfoFileName="$2"
	local _tmpDir="$3"
	local _logFile="$4"

	local _file=""
	local _buildDate=""
	local _basePath=""

	local _self="openbsd_getBasePath"

	_file="${_downloadBasePath}/${_buildinfoFileName}"

	# For snapshots create per build date directory structures
	if [ "$__OS_VERSION" = "snapshots" ]; then

		if [ ! -e "${_tmpDir}/${_buildinfoFileName}" ]; then

			# Get build date
			if ! downloadFile "$_file" "$_tmpDir"; then

				log "$_logFile" "[$_self] Download failed for \`$_file' but needed for OpenBSD ${__OS_VERSION}. Cannot continue!\n"
				return 1
			fi
		fi

		_buildDate=$( openbsd_getBuildDate "${_tmpDir}/${_buildinfoFileName}" )

		if [ $? -ne 0 ]; then

			log "$_logFile" "[$_self] Couldn't get build date from \`${_tmpDir}/${_buildinfoFileName}' but needed for OpenBSD ${__OS_VERSION}. Cannot continue!\n"
			return 1
		fi
		_basePath="${__BASE_PATH_PREFIX}/openbsd/${__OS_VERSION}/${_buildDate}"
	else
		_basePath="${__BASE_PATH_PREFIX}/openbsd/${__OS_VERSION}"
	fi

	echo "$_basePath"
	return
}


openbsd_getVersionNonDotted()
{
	local _downloadBasePath="$1"
	local _signatureFileName="$2"
	local _tmpDir="$3"
	local _logFile="$4"

	local _file
	local _versionNonDotted

	local _self="openbsd_getVersionNonDotted"

	if [ "$__OS_VERSION" = "snapshots" ]; then

		if [ ! -e "${_tmpDir}/${_signatureFileName}" ]; then

			_file="${_downloadBasePath}/${_signatureFileName}"

			if ! downloadFile "$_file" "$_tmpDir"; then

				log "$_logFile" "[$_self] Download failed for \`$_file' but needed for getting the non dotted version for OpenBSD snapshots.\n"
				return 1
			fi
		fi

		_versionNonDotted=$( openbsd_getNonDottedVersionFromSignatureFile "${_tmpDir}/${_signatureFileName}" )
	else
		_versionNonDotted=$( echo "$__OS_VERSION" | tr -d '.' )
	fi

	if [ $? -eq 0 ]; then

		echo "$_versionNonDotted"
		return
	else
		return 1
	fi
}


openbsd_downloadAllFiles()
{
	local _versionNonDotted="$1"
	local _signatureFileName="$2"
	local _hashFileName="$3"
	local _sets="$4"
	local _downloadBasePath="$5"
	local _tmpDir="$6"

	local _signifySupportSince="$7"
	local _hashFileSince="$8"
	local _platformPath="$9"
	local _logFile="${10}"

	local _filesToValidate
	local _set
	local _fileName
	local _file

	local _self="openbsd_downloadAllFiles"

	################################################################
	# Download files for validation
	################################################################
	# For OpenBSD versions since 5.5 download both hashfile and signature file
	if [ $_versionNonDotted -ge $_signifySupportSince ]; then

		# skip downloading of already downloaded and validated files
		if [ ! -e "${_platformPath}/${_signatureFileName}" ]; then

			_file="${_downloadBasePath}/${_signatureFileName}"

			if ! downloadFile "$_file" "$_tmpDir"; then

				log "$_logFile" "[$_self] Download failed for \`$_file' but possibly needed later for validation.\n"
				return 1
			fi
		fi

		# skip downloading of already downloaded and validated files
		if [ ! -e "${_platformPath}/${_hashFileName}" ]; then

			_file="${_downloadBasePath}/${_hashFileName}"

			if ! downloadFile "$_file" "$_tmpDir"; then

				log "$_logFile" "[$_self] Download failed for \`$_file' but possibly needed later for validation.\n"
				return 1
			fi
		fi

	# For OpenBSD versions since 4.6 and until 5.4 download only the hashfile
	elif [ $_versionNonDotted -ge $_hashFileSince ]; then

		# skip downloading of already downloaded and validated files
		if [ ! -e "${_platformPath}/${_hashFileName}" ]; then

			_file="${_downloadBasePath}/${_hashFileName}"

			if ! downloadFile "$_file" "$_tmpDir"; then

				log "$_logFile" "[$_self] Download failed for \`$_file' but possibly needed later for validation.\n"
				return 1
			fi
		fi

	# For older OpenBSD versions no validation is possible
	else
		:
	fi
	################################################################


	################################################################
	# Download sets
	################################################################
	for _set in $_sets; do

		_fileName="${_set}${_versionNonDotted}.tgz"

		# skip downloading of already downloaded and validated files
		if [ ! -e "${_platformPath}/${_fileName}" ]; then

			_file="${_downloadBasePath}/${_fileName}"

			if ! downloadFile "$_file" "$_tmpDir"; then

				log "$_logFile" "[$_self] Download failed for set \`$_file'.\n"
				return 1
			fi

			if [ "EMPTY${_filesToValidate}" = "EMPTY" ]; then

				_filesToValidate="${_fileName}"
			else
				_filesToValidate="${_filesToValidate} ${_fileName}"
			fi
		fi
	done
	################################################################


	################################################################
	# Download kernel
	################################################################
	# skip downloading of already downloaded and validated files
	if [ ! -e "${_platformPath}/${__KERNEL_TO_USE}" ]; then

		_file="${_downloadBasePath}/${__KERNEL_TO_USE}"

		if ! downloadFile "$_file" "$_tmpDir"; then

			log "$_logFile" "[$_self] Download failed for kernel \`$_file'.\n"
			return 1
		fi

		_filesToValidate="${_filesToValidate} ${__KERNEL_TO_USE}"
	fi
	################################################################


	################################################################
	# Download extra files
	################################################################
	for _fileName in $__ADDITIONAL_FILES_TO_DOWNLOAD; do

		# skip downloading of already downloaded and validated files
		if [ ! -e "${_platformPath}/${_fileName}" ]; then

			_file="${_downloadBasePath}/${_fileName}"

			if ! downloadFile "$_file" "$_tmpDir"; then

				log "$_logFile" "[$_self] Download failed for extra file \`$_file'.\n"
				return 1
			fi

			_filesToValidate="${_filesToValidate} ${_fileName}"
		fi
	done
	################################################################


	echo "$_filesToValidate"
	return 0
}


openbsd_validateAllFiles()
{
	local _tmpDir="$1"
	local _versionNonDotted="$2"
	local _filesToValidate="$3"
	local _signifySupportSince="$4"
	local _hashFileSince="$5"
	local _logFile="$6"
	local _platformPath="$7"
	local _signatureFileName="$8"
	local _hashFileName="$9"

	local _invalidFiles=$_FALSE
	local _version
	local _signatureFile="${_platformPath}/${_signatureFileName}"
	local _hashFile="${_platformPath}/${_hashFileName}"

	local _self="openbsd_validateAllFiles"

	log "$_logFile" "[$_self] Validating all files..."

	if [ -z "$_filesToValidate" ]; then

		log "$_logFile" " Skipped.\n"
		return 0
	else
		log "$_logFile" "\n"
	fi

	# change to temporary download directory
	cd "$_tmpDir"

	# Perform validity and signature test only, if files are from OpenBSD
	# 5.5 or newer and if the signify tool is available.
	if [ $_versionNonDotted -ge $_signifySupportSince -a \
	     -e "/etc/signify/openbsd-$_versionNonDotted-base.pub" ] && \
	   which signify 1>/dev/null 2>&1; then

		log "$_logFile" "[$_self] Checking validity of files with signify...\n"

		if [ ! -e "$_signatureFile" ]; then

			_signatureFile="${_tmpDir}/${_signatureFileName}"
		fi

		for _fileName in $_filesToValidate; do

			_file="${_tmpDir}/${_fileName}"

			# check validity
			if ! openbsd_isValidFileForSignify "$_openBsdVersionNonDotted" "${_signatureFile}" "$_file"; then

				log "$_logFile" "[$_self] \`${_file}' is invalid.\n"
				_invalidFiles=$_TRUE
			else
				log "$_logFile" "[$_self] \`${_file}' is valid.\n"
			fi
		done

	# Just do validity test
	elif [ $_versionNonDotted -ge $_hashFileSince ]; then

		_version=$( openbsd_nonDottedToDottedVersion "$_versionNonDotted" )

		log "$_logFile" "[$_self] Signify public keys missing for OpenBSD $_version or not running under OpenBSD.\n"
		log "$_logFile" "[$_self] Checking validity of files with SHA256 hashes...\n"

		if [ ! -e "$_hashFile" ]; then

			_hashFile="${_tmpDir}/${_hashFileName}"
		fi

		for _fileName in $_filesToValidate; do

			_file="${_tmpDir}/${_fileName}"

			# check validity
			if ! openbsd_isValidFileForSha256 "${_hashFile}" "$_file"; then

				log "$_logFile" "[$_self] \`${_file}' is invalid.\n"
				_invalidFiles=$_TRUE
			else
				log "$_logFile" "[$_self] \`${_file}' is valid.\n"
			fi
		done
	else
		log "$_logFile" "[$_self] Validation of files skipped because there is no signature nor hash file available for this OpenBSD version.\n"
		return 0
	fi

	if [ $_invalidFiles -eq $_TRUE ]; then

		return 1
	else
		return 0
	fi
}


openbsd_extractAllSets()
{
	local _sets="$1"
	local _versionNonDotted="$2"
	local _tmpDir="$3"
	local _rootPath="$4"
	local _platformPath="$5"
	local _logFile="$6"

	local _logOfOperation="$_tmpDir/untarFile.log"

	local _builtinEtcSetFile

	local _self="openbsd_extractAllSets"

	log "$_logFile" "[$_self] Extracting all sets...\n"

	if [ ! -e "$_rootPath" ]; then

		mkdir -p "$_rootPath"
	fi

	if [ $? -eq 0 ]; then

		cd "$_rootPath"
	else
		log "$_logFile" "[$_self] \`$_rootPath' could not be created."
		return 1
	fi

	for _set in $_sets; do

		_setFileName="${_set}${_versionNonDotted}.tgz"

		log "$_logFile" "[$_self] \`${_setFileName}'... "

		# The validated sets are located in the platform path
		#
		#           platform path
		#           +------------
		#           |
		#           |                host path
		#           |                +--------
		#           |                |
		#           |                |    root path
		#           |                |    +--------
		#           |                |    |
		# <PLATFORM>/hosts/<HOSTNAME>/root/
		if untarFile "${_platformPath}/${_setFileName}" "$_logOfOperation"; then

			log "$_logFile" "OK\n"
		else
			log "$_logFile" "ERROR. More details in \`$_logOfOperation'.\n"
			return 1
		fi
	done

	# Handling of "etc" set
	if [ $_versionNonDotted -ge 57 ]; then

		# the position of the builtin etc set changed with OpenBSD 5.9
		if [ $_versionNonDotted -lt 59 ]; then

			_builtinEtcSetFile="${_rootPath}/usr/share/sysmerge/etc.tgz"
		else
			_builtinEtcSetFile="${_rootPath}/var/sysmerge/etc.tgz"
		fi

		log "$_logFile" "[$_self] \`$_builtinEtcSetFile'... "

		if untarFile "$_builtinEtcSetFile" "$_logOfOperation"; then

			log "$_logFile" "OK\n"
		else
			log "$_logFile" "ERROR. More details in \`$_logOfOperation'.\n"
			return 1
		fi
	fi

	return 0
}


openbsd_configureSwapSpace()
{
	local _swapPath="$1"
	local _hostPath="$2"
	local _rootPath="$3"
	local _tmpDir="$4"
	local _logFile="$5"

	local _logOfOperation="$_tmpDir/swapFileCreation.log"

	local _self="openbsd_configureSwapSpace"

	log "$_logFile" "[$_self] Configuring swap space... "

	if createSwapFile "$_swapPath" \
	                  "$_logOfOperation"; then

		rm "$_logOfOperation"
	else
		log "$_logFile" "ERROR. More details in \`$_logOfOperation'.\n"
		return 1
	fi

	# Create mountpoint for swap space
	mkdir -m og-rwx,u-x -p "${_rootPath}/swap"

	if [ $? -eq 0 ]; then

		log "$_logFile" "OK\n"
		return 0
	else
		log "$_logFile" "ERROR. Couldn't create mountpoint for swap space \`${_rootPath}/swap'\n"
		return 1
	fi
}


openbsd_configureNetwork()
{
	local _rootPath="$1"
	local _logFile="$2"

	local _logOfOperation="$_tmpDir/networkConfiguration.log"

	local _self="openbsd_configureNetwork"

	log "$_logFile" "[$_self] Creating \`/etc/myname'... "
	echo "${__HOSTNAME}.${__DOMAIN}" 1> "${_rootPath}/etc/myname" \
	                                 2> "$_logOfOperation"
	if [ $? -eq 0 ]; then

		log "$_logFile" "OK\n"
	else
		log "$_logFile" "ERROR. More details in \`$_logOfOperation'.\n"
		return 1
	fi


	log "$_logFile" "[$_self] Creating \`/etc/hosts'... "
	cat 1> "${_rootPath}/etc/hosts" \
	    2> "$_logOfOperation" <<-EOF
		127.0.0.1       localhost
		::1             localhost6

		${__IP_ADDRESS} ${__HOSTNAME}.${__DOMAIN} ${__HOSTNAME}
	EOF

	if [ $? -eq 0 ]; then

		log "$_logFile" "OK\n"
	else
		log "$_logFile" "ERROR. More details in \`$_logOfOperation'.\n"
		return 1
	fi


	log "$_logFile" "[$_self] Creating \`/etc/mygate'... "
	echo "$__GATEWAY_ADDRESS" 1> "${_rootPath}/etc/mygate" \
	                          2> "$_logOfOperation"
	if [ $? -eq 0 ]; then

		log "$_logFile" "OK\n"
	else
		log "$_logFile" "ERROR. More details in \`$_logOfOperation'.\n"
		return 1
	fi


	log "$_logFile" "[$_self] Creating \`/etc/resolv.conf'... "
	cat 1> "${_rootPath}/etc/resolv.conf" \
	    2> "$_logOfOperation" <<-EOF
		nameserver ${__DNS_SERVER_ADDRESS}
		domain ${__DOMAIN}
		search ${__DOMAIN}
	EOF

	if [ $? -eq 0 ]; then

		log "$_logFile" "OK\n"
	else
		log "$_logFile" "ERROR. More details in \`$_logOfOperation'.\n"
		return 1
	fi

	rm -f "$_logOfOperation" || true

	return
}


openbsd_installKernel()
{
	local _rootPath="$1"
	local _platformPath="$2"
	local _tmpDir="$3"
	local _logFile="$4"

	local _logOfOperation="${_tmpDir}/kernelInstallation.log"
	local _command=""

	local _self="openbsd_installKernel"

	log "$_logFile" "[$_self] Installing kernel... "

	_command="cp "${_platformPath}/${__KERNEL_TO_USE}" "${_rootPath}/""
	echo "$_command" > "$_logOfOperation"
	$_command 2>&1 1>> "$_logOfOperation"

	if [ $? -eq 0 ]; then

		rm -f "$_logOfOperation"
	else
		log "$_logFile" "ERROR. More details in \`$_logOfOperation'.\n"
		return 1
	fi

	if [ "${__KERNEL_TO_USE}" != "bsd" ]; then

		_command="ln -s "${__KERNEL_TO_USE}" "${_rootPath}/bsd""
		echo "$_command" > "$_logOfOperation"
		$_command 2>&1 1>> "$_logOfOperation"

		if [ $? -eq 0 ]; then

			rm -f "$_logOfOperation"
			log "$_logFile" "OK\n"
			return 0
		else
			log "$_logFile" "ERROR. More details in \`$_logOfOperation'.\n"
			return 1
		fi
	fi

	log "$_logFile" "OK\n"
	return 0
}


openbsd_createAllDevices()
{
	local _rootPath="$1"
	local _logFile="$2"

	local _self="openbsd_createAllDevices"

	log "$_logFile" "[$_self] Creating all devices... "

	cd "${_rootPath}/dev"

	if [ $? -ne 0 ]; then

		log "$_logFile" "ERROR. Change directory failed.\n"
		return 1
	fi

	./MAKEDEV all

	if [ $? -eq 0 ]; then

		log "$_logFile" "OK\n"
		return 0
	else
		log "$_logFile" "ERROR. Device creation failed.\n"
		return 1
	fi
}


openbsd_createConsoleOnly()
{
	local _rootPath="$1"
	local _logFile="$2"

	local _self="openbsd_createConsoleOnly"

	log "$_logFile" "[$_self] Creating console device only... "

	cd "${_rootPath}/dev"

	if [ $? -ne 0 ]; then

		log "$_logFile" "ERROR. Change directory failed.\n"
		return 1
	fi

	mknod -m og-r console c 0 0

	if [ $? -eq 0 ]; then

		log "$_logFile" "OK\n"
		return 0
	else
		log "$_logFile" "ERROR. Device creation failed.\n"
		return 1
	fi
}


openbsd_configureFstab()
{
	local _rootPath="$1"
	local _swapPath="$2"
	local _logFile="$3"

	local _self="openbsd_configureFstab"

	log "$_logFile" "[$_self] Configuring fstab... "

	cd "${_rootPath}/etc"

	if [ $? -ne 0 ]; then

		log "$_logFile" "ERROR. Change directory failed.\n"
		return 1
	fi

	cat > fstab <<-EOF
		${__NFS_SERVER_ADDRESS}:${_rootPath} / nfs rw,tcp,nfsv3 0 0
		${__NFS_SERVER_ADDRESS}:${_swapPath} none swap sw,nfsmntpt=/swap,tcp
	EOF

	if [ $? -eq 0 ]; then

		log "$_logFile" "OK\n"
		return 0
	else
		log "$_logFile" "ERROR. Configuration failed.\n"
		return 1
	fi
}


openbsd_installNfsrbMarkerFiles()
{
	local _downloadBasePath="$1"
	local _buildInfoFileName="$2"
	local _tmpDir="$3"
	local _platformPath="$4"
	local _rootPath="$5"

	local _buildDate

	_buildDate=$( openbsd_getBuildDate "${_platformPath}/${_buildinfoFileName}" )

	if [ $? -ne 0 -o \
	     -z "$_buildDate" ]; then

		_buildDate="unknown"
	fi

	#echo -n "Placing version number and build date in \`${_rootPath}/etc/nfsrb_openbsd_version'... "
	echo "$__OS_VERSION ($_buildDate)" > "${_rootPath}/etc/nfsrb_openbsd_version" || return 1
	#echo "OK"

	# Place info about the used nfsrb version in "/etc/nfsrb"
	#echo -n "Placing nfsrb version number in \`${_rootPath}/etc/nfsrb_version'... "
	echo "$_NFSRB_VERSION" > "${_rootPath}/etc/nfsrb_version" || return 1
	#echo "OK"

	return 0
}


openbsd_makeFileSystem()
{
	local _defaultSets="$1"
	local _defaultSetsSince57="$2"
	local _signifySupportSince="$3"
	local _hashFileSince="$4"
	local _signatureFileName="$5"
	local _buildinfoFileName="$6"
	local _hashFileName="$7"
	local _nfsrb_cmdlineHash="$8"

	local _tmpDir
	local _logFile
	local _downloadBasePath
	local _basePath
	local _platformPath
	local _hostPath
	local _rootPath
	local _swapPath
	local _versionNonDotted
	local _filesToValidate

	################################################################
	# STAGE #0 Preparation
	################################################################
	# Create temporary directory for downloading files but reuse
	# temporary directory of last run for the same configuration
	# file
	if [ -s "${_NFSRB_CONFIG_DIR}/${_nfsrb_cmdlineHash}.tmpdir" ]; then

		_tmpDir=$( cat "${_NFSRB_CONFIG_DIR}/${_nfsrb_cmdlineHash}.tmpdir" )
	fi

	if [ ! -e "$_tmpDir" ]; then

		_tmpDir=$( mktemp -d -t "nfsrb.XXXXXXXXXX" )

		if [ $? -eq 0 ]; then

			echo "$_tmpDir" > "${_NFSRB_CONFIG_DIR}/${_nfsrb_cmdlineHash}.tmpdir"
		else
			echo "Couldn't create temporary directory \`$_tmpDir'."
			return 1
		fi
	fi

	_logFile="$_tmpDir/nfsrb.log"
	log "$_logFile" "nfsrb: Starting execution.\n"


	################################################################
	# Path construction
	################################################################
	# Construct download base path on download mirror service
	# _downloadMirror is given with trailing slash as it is referencing a directory, so no
	# slash needed after it!
	_downloadBasePath="${__DOWNLOAD_MIRROR}${__OS_VERSION}/${__PLATFORM}"

	# Construct base path for local files
	_basePath=$( openbsd_getBasePath "$_downloadBasePath" \
	                                 "$_buildinfoFileName" \
	                                 "$_tmpDir" \
	                                 "$_logFile" )
	if [ $? -ne 0 ]; then

		echo "Cannot determine base path. Check \"$_logFile\" for more details."
		return 1
	fi

	# Construct platform bath
	_platformPath="${_basePath}/${__PLATFORM}"

	# Construct host path
	_hostPath="${_platformPath}/hosts/${__HOSTNAME}"

	# Construct root and swap paths
	_rootPath="${_hostPath}/root"
	_swapPath="${_hostPath}/swap"

	mkdir -p "$_hostPath"

	if [ $? -ne 0 ]; then

		echo "Couldn't create host path \`$_hostPath'."
		return 1
	else
		# Save files in the platform directory
		cd "$_platformPath"
	fi
	################################################################

	_versionNonDotted=$( openbsd_getVersionNonDotted "$_downloadBasePath" \
	                                                 "$_signatureFileName" \
	                                                 "$_tmpDir" \
	                                                 "$_logFile" )
	if [ $? -ne 0 ]; then

		echo "Couldn't determine non dotted version. Check \"$_logFile\" for more details."
		return 1
	fi

	# Combine default and additional sets
	if [ $_versionNonDotted -lt 57 ]; then

		_sets="$_defaultSets $__ADDITIONAL_SETS_TO_DOWNLOAD"
	else
		_sets="$_defaultSetsSince57 $__ADDITIONAL_SETS_TO_DOWNLOAD"
	fi
	################################################################


	################################################################
	# STAGE #1 Download and validate all wanted files
	################################################################
	echo -n "Now downloading files... "

	_filesToValidate=$( openbsd_downloadAllFiles "$_versionNonDotted" \
	                                             "$_signatureFileName" \
	                                             "$_hashFileName" \
	                                             "$_sets" \
	                                             "$_downloadBasePath" \
	                                             "$_tmpDir" \
	                                             "$_signifySupportSince" \
	                                             "$_hashFileSince" \
	                                             "$_platformPath" \
	                                             "$_logFile" )
	if [ $? -ne 0 ]; then

		echo "Maybe try again later. Check \"$_logFile\" for more details."
		return 1
	else
		echo "OK"
	fi

	echo -n "Now validating files... "

	if ! openbsd_validateAllFiles "$_tmpDir" \
	                              "$_versionNonDotted" \
	                              "$_filesToValidate" \
	                              "$_signifySupportSince" \
	                              "$_hashFileSince" \
	                              "$_logFile" \
	                              "$_platformPath" \
	                              "$_signatureFileName" \
	                              "$_hashFileName"; then

		echo "Detected at least one invalid file in \`$_tmpDir'. Cannot continue. Please delete invalid file(s) and try again later. Check \"$_logFile\" for more details."
		return 1
	else
		if [ ! -z "$_filesToValidate" ]; then

			cd "$_tmpDir"

			# move all downloaded files to final destination dir ($_hostPath/..)
			mv $_filesToValidate "${_platformPath}/"

			if [ -e "$_signatureFileName" ]; then

				mv "$_signatureFileName" "${_platformPath}/"
			fi

			if [ -e "$_hashFileName" ]; then

				mv "$_hashFileName" "${_platformPath}/"
			fi

			if [ -e "$_buildinfoFileName" ]; then

				mv "$_buildinfoFileName" "${_platformPath}/"
			fi

			# Return to host path
			cd "$_hostPath"
		fi

		echo "OK"
	fi
	################################################################


	################################################################
	# STAGE #2 Extract and configure the file system
	################################################################
	echo -n "Now extracting sets... "

	if ! openbsd_extractAllSets "$_sets" \
	                            "$_versionNonDotted" \
	                            "$_tmpDir" \
	                            "$_rootPath" \
	                            "$_platformPath" \
	                            "$_logFile"; then

		echo "Problems during extraction of sets. Check \"$_logFile\" for more details."
		return 1
	else
		echo "OK"
	fi

	echo "Now configuring file system:"


	echo -n "Installing kernel... "

	if ! openbsd_installKernel "$_rootPath" \
	                           "$_platformPath" \
	                           "$_tmpDir" \
	                           "$_logFile"; then

		echo "Problems during installation of the kernel. Check \"$_logFile\" for more details."
		return 1
	else
		echo "OK"
	fi

	################################################################
	# Swap configuration
	################################################################
	echo -n "Configuring swap space... "

	if ! openbsd_configureSwapSpace "$_swapPath" \
	                                "$_hostPath" \
	                                "$_rootPath" \
	                                "$_tmpDir" \
	                                "$_logFile"; then

		echo "Problems during swap space configuration. Check \"$_logFile\" for more details."
		return 1
	else
		echo "OK"
	fi


	echo -n "Configuring network... "

	if ! openbsd_configureNetwork "$_rootPath" \
	                              "$_logFile"; then

		echo "Problems during network configuration. Check \"$_logFile\" for more details."
		return 1
	else
		echo "OK"
	fi

	################################################################
	# Device creation
	################################################################
	echo -n "Creating devices... "

	if [ $( uname -s ) = "OpenBSD" ]; then

		if ! openbsd_createAllDevices "$_rootPath" \
		                              "$_logFile"; then

			echo "ERROR. Device creation failed. Check \"$_logFile\" for more details."
			return 1
		else
			echo "OK"
		fi
	else
		if ! openbsd_createConsoleOnly "$_rootPath" \
		                               "$_logFile"; then

			echo "ERROR. Console creation failed. Check \"$_logFile\" for more details."
			return 1
		else
			echo "Only created \`/dev/console' as we're not running under OpenBSD. Please use root FS in single user mode and create devices manually (\`mount -uw / && cd /dev && ./MAKEDEV all\`) before going multi-user."
		fi
	fi

	################################################################
	# Configuration of file systems to mount
	################################################################
	echo -n "Configuring file systems... "

	if ! openbsd_configureFstab "$_rootPath" \
	                            "$_swapPath" \
	                            "$_logFile"; then

		echo "ERROR. Configuration failed. Check \"$_logFile\" for more details."
		return 1
	else
		echo "OK"
	fi

	################################################################
	# Install marker files
	################################################################
	# This is needed for gen-keys-openbsd to be able to generate the correct
	# keys depending on the version of the target OS. In addition its also
	# useful to quickly determine the version of the target OS if it is not
	# running and if it is not stored in a directory hierarchy that shows
	# the version.

	echo -n "Installing nfsrb marker files... "

	if ! openbsd_installNfsrbMarkerFiles "$_downloadBasePath" \
	                                     "$_buildInfoFileName" \
	                                     "$_tmpDir" \
	                                     "$_platformPath" \
	                                     "$_rootPath"; then

		echo "ERROR: Installation failed. Check \"$_logFile\" for more details."
		return 1
	else
		echo "OK"
	fi



	################################################################
	# STAGE #3 Post actions
	################################################################
	#
	# * key generation
	# * post release updates (erratas, etc.)

	# prepare nfsrb environment file
	#cat > "${_tmpDir}/nfsrb_environment" <<-EOF
	#	_nfsrb_hostname="$_hostname"
	#	_nfsrb_domain="$_domain"
	#	_nfsrb_ipAddres="$_ipAddress"
	#	_nfsrb_bootNetworkInterface="$_bootNetworkInterface"
	#	_nfsrb_swapFileSize="$_swapFileSize"
	#	_nfsrb_dnsServerAddress="$_dnsServerAddress"
	#	_nfsrb_gatewayAddress="$_gatewayAddress"
	#	_nfsrb_nfsServerAddress="$_nfsServerAddress"
	#	_nfsrb_downloadMirror="$_downloadMirror"
	#	_nfsrb_version="$_version"
	#	_nfsrb_platform="$_platform"
	#	_nfsrb_basePathPrefix="$_basePathPrefix"
	#	_nfsrb_additionalSetsToDownload="$_additionalSetsToDownload"
	#	_nfsrb_kernelToUse="$_kernelToUse"
	#	_nfsrb_additionalFilesToDownload="$_additionalFilesToDownload"

	#	_nfsrb_defaultSets="$_defaultSets"
	#	_nfsrb_defaultSetsSince57="$_defaultSetsSince57"
	#	_nfsrb_signifySupportSince="$_signifySupportSince"
	#	_nfsrb_hashFileSince="$_hashFileSince"
	#	_nfsrb_signatureFileName="$_signatureFileName"
	#	_nfsrb_buildinfoFileName="$_buildinfoFileName"
	#	_nfsrb_hashFileName="$_hashFileName"

	#	_nfsrb_nfsrbConfigDir="$_nfsrbConfigDir"
	#	_nfsrb_configurationFileHash="$_configurationFileHash"
	#	_nfsrb_nfsrbVersion="$_nfsrbVersion"

	#	_nfsrb_tmpDir="$_tmpDir"
	#	_nfsrb_logFile="$_logFile"
	#	_nfsrb_downloadBasePath="$_downloadBasePath"
	#	_nfsrb_basePath="$_basePath"
	#	_nfsrb_platformPath="$_platformPath"
	#	_nfsrb_hostPath="$_hostPath"
	#	_nfsrb_rootPath="$_rootPath"
	#	_nfsrb_swapPath="$_swapPath"
	#	_nfsrb_versionNonDotted="$_versionNonDotted"
	#	_nfsrb_filesToValidate="$_filesToValidate"
	#EOF

	echo -n "Executing post actions... "

	if ! addFiles "$_rootPath" \
	              "$_logFile"; then

		return 1
	else
		echo "OK"
	fi

	return
}


########################################################################
# Functionality specific to NetBSD file systems
########################################################################

netbsd_isValidFileForSha512()
{
	local _hashFile="$1"
	local _file="$2"

	local _fileName=$( basename "$_file" )

	local _tempHashFile=$( mktemp )
	local _validityCheckReturned=1

	grep "($_fileName)" "$_hashFile" > "$_tempHashFile"

	if [ $( uname -s ) = "OpenBSD" ]; then

		sha512 -c "$_tempHashFile" 1>/dev/null 2>&1

	elif [ $( uname -s ) = "NetBSD" ]; then

		cksum -c -a SHA512 "$_tempHashFile" 1>/dev/null 2>&1

	elif [ $( uname -s ) = "Linux" ]; then

		sha512sum -c "$_tempHashFile" 1>/dev/null 2>&1
	fi

	_validityCheckReturned=$?

	rm "$_tempHashFile"

	return $_validityCheckReturned
}


netbsd_downloadAllFiles()
{
	local _hashFileName="$1"
	local _sets="$2"
	local _downloadBasePath="$3"
	local _tmpDir="$4"

	local _platformPath="$5"
	local _logFile="$6"
	local _osVersion="$7"

	local _osVersionNonDotted
	local _filesToValidate
	local _set
	local _fileName
	local _file

	local _self="netbsd_downloadAllFiles"

	mkdir -p "${_tmpDir}/binary/sets"

	################################################################
	# Download file for validation of sets
	################################################################
	# skip downloading of already downloaded and validated files
	if [ ! -e "${_platformPath}/binary/sets/${_hashFileName}" ]; then

		_file="${_downloadBasePath}/binary/sets/${_hashFileName}"

		if ! downloadFile "$_file" "${_tmpDir}/binary/sets/"; then

			log "$_logFile" "[$_self] Download failed for \`$_file' but possibly needed later for validation.\n"
			return 1
		fi
	fi
	################################################################


	################################################################
	# Download sets
	################################################################
	for _set in $_sets; do

		_osVersionNonDotted=$( echo "$_osVersion" | tr -d '.' )

		if [ "$_osVersionNonDotted" -ge "90" ]; then

			_fileName="${_set}.tar.xz"
		else
			_fileName="${_set}.tgz"
		fi

		# skip downloading of already downloaded and validated files
		if [ ! -e "${_platformPath}/binary/sets/${_fileName}" ]; then

			_file="${_downloadBasePath}/binary/sets/${_fileName}"

			if ! downloadFile "$_file" "${_tmpDir}/binary/sets/"; then

				log "$_logFile" "[$_self] Download failed for set \`$_file'.\n"
				return 1
			fi

			if [ "EMPTY${_filesToValidate}" = "EMPTY" ]; then

				_filesToValidate="/binary/sets/${_fileName}"
			else
				_filesToValidate="${_filesToValidate} /binary/sets/${_fileName}"
			fi
		fi
	done
	################################################################

	mkdir -p "${_tmpDir}/binary/kernel"

	################################################################
	# Download file for validation of kernel
	################################################################
	# skip downloading of already downloaded and validated files
	if [ ! -e "${_platformPath}/binary/kernel/${_hashFileName}" ]; then

		_file="${_downloadBasePath}/binary/kernel/${_hashFileName}"

		if ! downloadFile "$_file" "${_tmpDir}/binary/kernel"; then

			log "$_logFile" "[$_self] Download failed for \`$_file' but possibly needed later for validation.\n"
			return 1
		fi
	fi

	################################################################


	################################################################
	# Download kernel
	################################################################
	# skip downloading of already downloaded and validated files
	if [ ! -e "${_platformPath}/binary/kernel/${__KERNEL_TO_USE}" ]; then

		_file="${_downloadBasePath}/binary/kernel/${__KERNEL_TO_USE}"

		if ! downloadFile "$_file" "${_tmpDir}/binary/kernel"; then

			log "$_logFile" "[$_self] Download failed for kernel \`$_file'.\n"
			return 1
		fi

		_filesToValidate="${_filesToValidate} /binary/kernel/${__KERNEL_TO_USE}"
	fi
	################################################################


	################################################################
	# Download extra files
	################################################################
	for _filePath in $__ADDITIONAL_FILES_TO_DOWNLOAD; do

		# skip downloading of already downloaded and validated files
		if [ ! -e "${_platformPath}/${_filePath}" ]; then

			_file="${_downloadBasePath}/${_filePath}"

			_subPath=$( dirname "$_filePath" )

			if [ ! -e "${_tmpDir}/${_subPath}" ]; then

				mkdir -p "${_tmpDir}/${_subPath}"
			fi

			if ! downloadFile "$_file" "${_tmpDir}/${_subPath}"; then

				log "$_logFile" "[$_self] Download failed for extra file \`$_file'.\n"
				return 1
			fi

			# Additional files not below `binary` cannot be validated as e.g. the dirs
			# below `installation` or `installation` itself don't contain files with
			# hash values.
			#_filesToValidate="${_filesToValidate} ${_filePath}"
		fi
	done
	################################################################

	echo "$_filesToValidate"
	return 0
}


netbsd_validateAllFiles()
{
	local _tmpDir="$1"
	local _filesToValidate="$2"
	local _logFile="$3"
	local _platformPath="$4"
	local _hashFileName="$5"

	local _invalidFiles=$_FALSE
	local _version

	local _self="netbsd_validateAllFiles"

	log "$_logFile" "[$_self] Validating all files..."

	if [ -z "$_filesToValidate" ]; then

		log "$_logFile" " Skipped.\n"
		return 0
	else
		log "$_logFile" "\n"
	fi

	# change to temporary download directory
	cd "$_tmpDir"

	# Just do validity test
	log "$_logFile" "[$_self] Checking validity of files with SHA512 hashes...\n"

	for _filePath in $_filesToValidate; do

		_file="${_tmpDir}/${_filePath}"
		_fileParentDir=$( dirname ${_file} )
		# Todo:
		# This does not take into account that the hash flle could have been
		# alread moved below $_platformPath if considered sane during the last
		# try.
		_hashFile="${_fileParentDir}/${_hashFileName}"

		cd ${_fileParentDir}

		# check validity
		if ! netbsd_isValidFileForSha512 "${_hashFile}" "$_file"; then

			log "$_logFile" "[$_self] \`${_file}' is invalid.\n"
			_invalidFiles=$_TRUE
		else
			log "$_logFile" "[$_self] \`${_file}' is valid.\n"
		fi

		cd ${_tmpDir}
	done

	if [ $_invalidFiles -eq $_TRUE ]; then

		return 1
	else
		return 0
	fi
}


netbsd_extractAllSets()
{
	local _sets="$1"
	local _tmpDir="$2"
	local _rootPath="$3"
	local _platformPath="$4"
	local _logFile="$5"
	local _osVersion="$6"

	local _osVersionNonDotted
	local _logOfOperation="$_tmpDir/untarFile.log"

	local _builtinEtcSetFile

	local _self="netbsd_extractAllSets"

	log "$_logFile" "[$_self] Extracting all sets...\n"

	if [ ! -e "$_rootPath" ]; then

		mkdir -p "$_rootPath"
	fi

	if [ $? -eq 0 ]; then

		cd "$_rootPath"
	else
		log "$_logFile" "[$_self] \`$_rootPath' could not be created."
		return 1
	fi

	for _set in $_sets; do

		_osVersionNonDotted=$( echo "$_osVersion" | tr -d '.' )

                if [ "$_osVersionNonDotted" -ge "90" ]; then

                        _setFileName="${_set}.tar.xz"
                else
                        _setFileName="${_set}.tgz"
                fi

		log "$_logFile" "[$_self] \`${_setFileName}'... "

		# The validated sets are located in the platform path below
		# `binary/sets`
		#
		#           platform path
		#           +------------
		#           |
		#           |                host path
		#           |                +--------
		#           |                |
		#           |                |    root path
		#           |                |    +--------
		#           |                |    |
		# <PLATFORM>/hosts/<HOSTNAME>/root/
		if untarFile "${_platformPath}/binary/sets/${_setFileName}" "$_logOfOperation"; then

			log "$_logFile" "OK\n"
		else
			log "$_logFile" "ERROR. More details in \`$_logOfOperation'.\n"
			return 1
		fi
	done

	return 0
}


netbsd_installKernel()
{
	local _rootPath="$1"
	local _platformPath="$2"
	local _tmpDir="$3"
	local _logFile="$4"

	local _logOfOperation="${_tmpDir}/kernelInstallation.log"
	local _command=""

	local _self="netbsd_installKernel"

	log "$_logFile" "[$_self] Installing kernel... "

	_command="cp "${_platformPath}/binary/kernel/${__KERNEL_TO_USE}" "${_rootPath}/""
	echo "$_command" > "$_logOfOperation"
	$_command 2>&1 1>> "$_logOfOperation"

	if [ $? -eq 0 ]; then

		rm -f "$_logOfOperation"
	else
		log "$_logFile" "ERROR. More details in \`$_logOfOperation'.\n"
		return 1
	fi

	# TODO:
	# Check if not "netbsd.gz" was meant here, because the symlink is named
	# like that.
	if [ "${__KERNEL_TO_USE}" != "netbsd" ]; then

		_command="ln -s "${__KERNEL_TO_USE}" "${_rootPath}/netbsd.gz""
		echo "$_command" > "$_logOfOperation"
		$_command 2>&1 1>> "$_logOfOperation"

		if [ $? -eq 0 ]; then

			rm -f "$_logOfOperation"
			log "$_logFile" "OK\n"
			return 0
		else
			log "$_logFile" "ERROR. More details in \`$_logOfOperation'.\n"
			return 1
		fi
	fi

	log "$_logFile" "OK\n"
	return 0
}


netbsd_configureSwapSpace()
{
	local _swapPath="$1"
	local _hostPath="$2"
	local _rootPath="$3"
	local _tmpDir="$4"
	local _logFile="$5"

	local _logOfOperation="$_tmpDir/swapFileCreation.log"

	local _self="netbsd_configureSwapSpace"

	log "$_logFile" "[$_self] Configuring swap space... "

	if createSwapFile "$_swapPath" \
	                  "$_logOfOperation"; then

		rm "$_logOfOperation"
	else
		log "$_logFile" "ERROR. More details in \`$_logOfOperation'.\n"
		return 1
	fi

	# Create mountpoint for swap space
	mkdir -m og-rwx,u-x -p "${_rootPath}/swap"

	if [ $? -eq 0 ]; then

		log "$_logFile" "OK\n"
		return 0
	else
		log "$_logFile" "ERROR. Couldn't create mountpoint for swap space \`${_rootPath}/swap'\n"
		return 1
	fi
}


netbsd_configureNetwork()
{
	local _rootPath="$1"
	local _logFile="$2"

	local _logOfOperation="$_tmpDir/networkConfiguration.log"

	local _self="netbsd_configureNetwork"

	log "$_logFile" "[$_self] Creating \`/etc/myname'... "
	echo "${__HOSTNAME}.${__DOMAIN}" 1> "${_rootPath}/etc/myname" \
	                                 2> "$_logOfOperation"
	if [ $? -eq 0 ]; then

		log "$_logFile" "OK\n"
	else
		log "$_logFile" "ERROR. More details in \`$_logOfOperation'.\n"
		return 1
	fi

	log "$_logFile" "[$_self] Creating \`/etc/hosts'... "
	cat 1> "${_rootPath}/etc/hosts" \
	    2> "$_logOfOperation" <<-EOF
		127.0.0.1       localhost
		::1             localhost6

		${__IP_ADDRESS} ${__HOSTNAME}.${__DOMAIN} ${__HOSTNAME}
	EOF

	if [ $? -eq 0 ]; then

		log "$_logFile" "OK\n"
	else
		log "$_logFile" "ERROR. More details in \`$_logOfOperation'.\n"
		return 1
	fi


	log "$_logFile" "[$_self] Creating \`/etc/mygate'... "
	echo "$__GATEWAY_ADDRESS" 1> "${_rootPath}/etc/mygate" \
	                          2> "$_logOfOperation"
	if [ $? -eq 0 ]; then

		log "$_logFile" "OK\n"
	else
		log "$_logFile" "ERROR. More details in \`$_logOfOperation'.\n"
		return 1
	fi


	log "$_logFile" "[$_self] Creating \`/etc/resolv.conf'... "
	cat 1> "${_rootPath}/etc/resolv.conf" \
	    2> "$_logOfOperation" <<-EOF
		nameserver ${__DNS_SERVER_ADDRESS}
		domain ${__DOMAIN}
		search ${__DOMAIN}
	EOF

	if [ $? -eq 0 ]; then

		log "$_logFile" "OK\n"
	else
		log "$_logFile" "ERROR. More details in \`$_logOfOperation'.\n"
		return 1
	fi

	rm -f "$_logOfOperation" || true

	return
}


netbsd_configureFstab()
{
	local _rootPath="$1"
	local _swapPath="$2"
	local _logFile="$3"

	local _self="netbsd_configureFstab"

	log "$_logFile" "[$_self] Configuring fstab... "

	cd "${_rootPath}/etc"

	if [ $? -ne 0 ]; then

		log "$_logFile" "ERROR. Change directory failed.\n"
		return 1
	fi

	cat > fstab <<-EOF
		${__NFS_SERVER_ADDRESS}:${_rootPath} / nfs rw,tcp,nfsv3 0 0
		${__NFS_SERVER_ADDRESS}:${_swapPath} none swap sw,nfsmntpt=/swap,tcp
	EOF

	if [ $? -eq 0 ]; then

		log "$_logFile" "OK\n"
		return 0
	else
		log "$_logFile" "ERROR. Configuration failed.\n"
		return 1
	fi
}


netbsd_installNfsrbMarkerFiles()
{
	local _downloadBasePath="$1"
	local _tmpDir="$2"
	local _platformPath="$3"
	local _rootPath="$4"

	if [ $? -ne 0 -o \
	     -z "$_buildDate" ]; then

		_buildDate="unknown"
	fi

	#echo -n "Placing version number and build date in \`${_rootPath}/etc/nfsrb_openbsd_version'... "
	echo "$__OS_VERSION ($_buildDate)" > "${_rootPath}/etc/nfsrb_netbsd_version" || return 1
	#echo "OK"

	# Place info about the used nfsrb version in "/etc/nfsrb"
	#echo -n "Placing nfsrb version number in \`${_rootPath}/etc/nfsrb_version'... "
	echo "$__NFSRB_VERSION" > "${_rootPath}/etc/nfsrb_version" || return 1
	#echo "OK"

	return 0
}


netbsd_makeFileSystem()
{
	local _defaultSets="$1"
	local _hashFileName="$2"
	local _nfsrb_cmdlineHash="$3"

	local _tmpDir
	local _logFile
	local _downloadBasePath
	local _basePath
	local _platformPath
	local _hostPath
	local _rootPath
	local _swapPath
	local _versionNonDotted
	local _filesToValidate

	################################################################
	# STAGE #0 Preparation
	################################################################
	# Create temporary directory for downloading files but reuse
	# temporary directory of last run for the same configuration
	# file
	if [ -s "${_NFSRB_CONFIG_DIR}/${_nfsrb_cmdlineHash}.tmpdir" ]; then

		_tmpDir=$( cat "${_NFSRB_CONFIG_DIR}/${_nfsrb_cmdlineHash}.tmpdir" )
	fi

	if [ ! -e "$_tmpDir" ]; then

		_tmpDir=$( mktemp -d -t "nfsrb.XXXXXXXXXX" )

		if [ $? -eq 0 ]; then

			echo "$_tmpDir" > "${_NFSRB_CONFIG_DIR}/${_nfsrb_cmdlineHash}.tmpdir"
		else
			echo "Couldn't create temporary directory \`$_tmpDir'."
			return 1
		fi
	fi

	_logFile="$_tmpDir/nfsrb.log"
	log "$_logFile" "nfsrb: Starting execution.\n"

	################################################################
	# Path construction
	################################################################
	# Construct download base path on download mirror service
	# _downloadMirror is given with trailing slash as it is referencing a directory, so no
	# slash needed after it!
	_downloadBasePath="${__DOWNLOAD_MIRROR}NetBSD-${__OS_VERSION}/${__PLATFORM}"

	# Construct base path for local files
	_basePath="${__BASE_PATH_PREFIX}/${__OS}/NetBSD-${__OS_VERSION}"

	# Construct platform bath
	_platformPath="${_basePath}/${__PLATFORM}"

	# Construct host path
	# **NOTICE:** As NetBSD has multiple sub-dirs in the platform path, I added an
	# additional so-called `hosts` dir to contain the host file systems. Maybe this
	# scheme could be also used for OpenBSD?
	_hostPath="${_platformPath}/hosts/${__HOSTNAME}"

	# Construct root and swap paths
	_rootPath="${_hostPath}/root"
	_swapPath="${_hostPath}/swap"

	mkdir -p "$_hostPath"

	if [ $? -ne 0 ]; then

		echo "Couldn't create host path \`$_hostPath'."
		return 1
	else
		# Save files in the platform directory
		cd "$_platformPath"
	fi
	################################################################

	_sets="$_defaultSets $__ADDITIONAL_SETS_TO_DOWNLOAD"

	################################################################


	################################################################
	# STAGE #1 Download and validate all wanted files
	################################################################
	echo -n "Now downloading files... "

	_filesToValidate=$( netbsd_downloadAllFiles "$_hashFileName" \
	                                            "$_sets" \
	                                            "$_downloadBasePath" \
	                                            "$_tmpDir" \
	                                            "$_platformPath" \
	                                            "$_logFile" \
	                                            "$__OS_VERSION" )
	if [ $? -ne 0 ]; then

		echo "Maybe try again later. Check \"$_logFile\" for more details."
		return 1
	else
		echo "OK"
	fi

	echo -n "Now validating files... "

	if ! netbsd_validateAllFiles "$_tmpDir" \
	                             "$_filesToValidate" \
	                             "$_logFile" \
	                             "$_platformPath" \
	                             "$_hashFileName"; then

		echo "Detected at least one invalid file in \`$_tmpDir'. Cannot continue. Please delete invalid file(s) and try again later. Check \"$_logFile\" for more details."
		return 1
	else
		#if [ ! -z "$_filesToValidate" ]; then

			cd "$_tmpDir"

			# move all downloaded files to final destination dir
			for _filePath in $_filesToValidate $__ADDITIONAL_FILES_TO_DOWNLOAD; do

				_file="${_tmpDir}/${_filePath}"
				_fileParentDir=$( dirname $_filePath )
				_destinationDir="${_platformPath}/${_fileParentDir}"

				if [ ! -e "$_destinationDir" ]; then

					mkdir -p "$_destinationDir"
					# If the dest. dir wasn't existing earlier, the hashfile
					# also wasn't yet moved, so move it now and be done with
					# it.
					_hashFile="${_tmpDir}/${_fileParentDir}/${_hashFileName}"
					if [ -e "$_hashFile" ]; then

						mv "$_hashFile" "${_destinationDir}/"
					fi
				fi

				if [ -e "$_file" ]; then

					mv "$_file" "${_destinationDir}/"
				fi
			done

			# Return to host path
			cd "$_hostPath"
		#fi

		echo "OK"
	fi
	################################################################


	################################################################
	# STAGE #2 Extract and configure the file system
	################################################################
	echo -n "Now extracting sets... "

	if ! netbsd_extractAllSets "$_sets" \
	                           "$_tmpDir" \
	                           "$_rootPath" \
	                           "$_platformPath" \
	                           "$_logFile" \
	                           "$__OS_VERSION"; then

		echo "Problems during extraction of sets. Check \"$_logFile\" for more details."
		return 1
	else
		echo "OK"
	fi

	echo "Now configuring file system:"


	echo -n "Installing kernel... "

	if ! netbsd_installKernel "$_rootPath" \
	                          "$_platformPath" \
	                          "$_tmpDir" \
	                          "$_logFile"; then

		echo "Problems during installation of the kernel. Check \"$_logFile\" for more details."
		return 1
	else
		echo "OK"
	fi

	################################################################
	# Swap configuration
	################################################################
	echo -n "Configuring swap space... "

	if ! netbsd_configureSwapSpace "$_swapPath" \
	                               "$_hostPath" \
	                               "$_rootPath" \
	                               "$_tmpDir" \
	                               "$_logFile"; then

		echo "Problems during swap space configuration. Check \"$_logFile\" for more details."
		return 1
	else
		echo "OK"
	fi


	echo -n "Configuring network... "

	if ! netbsd_configureNetwork "$_rootPath" \
	                             "$_logFile"; then

		echo "Problems during network configuration. Check \"$_logFile\" for more details."
		return 1
	else
		echo "OK"
	fi

	################################################################
	# Configuration of file systems to mount
	################################################################
	echo -n "Configuring file systems... "

	if ! netbsd_configureFstab "$_rootPath" \
	                           "$_swapPath" \
	                           "$_logFile"; then

		echo "ERROR. Configuration failed. Check \"$_logFile\" for more details."
		return 1
	else
		echo "OK"
	fi

	################################################################
	# Install marker files
	################################################################
	# This is needed for gen-keys-openbsd to be able to generate the correct
	# keys depending on the version of the target OS. In addition its also
	# useful to quickly determine the version of the target OS if it is not
	# running and if it is not stored in a directory hierarchy that shows
	# the version.

	echo -n "Installing nfsrb marker files... "

	if ! netbsd_installNfsrbMarkerFiles "$_downloadBasePath" \
	                                    "$_tmpDir" \
	                                    "$_platformPath" \
	                                    "$_rootPath"; then

		echo "ERROR: Installation failed. Check \"$_logFile\" for more details."
		return 1
	else
		echo "OK"
	fi



	################################################################
	# STAGE #3 Post actions
	################################################################
	#
	# * key generation
	# * post release updates (erratas, etc.)

	# prepare nfsrb environment file
	#cat > "${_tmpDir}/nfsrb_environment" <<-EOF
	#	_nfsrb_hostname="$_hostname"
	#	_nfsrb_domain="$_domain"
	#	_nfsrb_ipAddres="$_ipAddress"
	#	_nfsrb_bootNetworkInterface="$_bootNetworkInterface"
	#	_nfsrb_swapFileSize="$_swapFileSize"
	#	_nfsrb_dnsServerAddress="$_dnsServerAddress"
	#	_nfsrb_gatewayAddress="$_gatewayAddress"
	#	_nfsrb_nfsServerAddress="$_nfsServerAddress"
	#	_nfsrb_downloadMirror="$_downloadMirror"
	#	_nfsrb_version="$_version"
	#	_nfsrb_platform="$_platform"
	#	_nfsrb_basePathPrefix="$_basePathPrefix"
	#	_nfsrb_additionalSetsToDownload="$_additionalSetsToDownload"
	#	_nfsrb_kernelToUse="$_kernelToUse"
	#	_nfsrb_additionalFilesToDownload="$_additionalFilesToDownload"

	#	_nfsrb_defaultSets="$_defaultSets"
	#	_nfsrb_defaultSetsSince57="$_defaultSetsSince57"
	#	_nfsrb_signifySupportSince="$_signifySupportSince"
	#	_nfsrb_hashFileSince="$_hashFileSince"
	#	_nfsrb_signatureFileName="$_signatureFileName"
	#	_nfsrb_buildinfoFileName="$_buildinfoFileName"
	#	_nfsrb_hashFileName="$_hashFileName"

	#	_nfsrb_nfsrbConfigDir="$_nfsrbConfigDir"
	#	_nfsrb_configurationFileHash="$_configurationFileHash"
	#	_nfsrb_nfsrbVersion="$_nfsrbVersion"

	#	_nfsrb_tmpDir="$_tmpDir"
	#	_nfsrb_logFile="$_logFile"
	#	_nfsrb_downloadBasePath="$_downloadBasePath"
	#	_nfsrb_basePath="$_basePath"
	#	_nfsrb_platformPath="$_platformPath"
	#	_nfsrb_hostPath="$_hostPath"
	#	_nfsrb_rootPath="$_rootPath"
	#	_nfsrb_swapPath="$_swapPath"
	#	_nfsrb_versionNonDotted="$_versionNonDotted"
	#	_nfsrb_filesToValidate="$_filesToValidate"
	#EOF

	echo -n "Executing post actions... "

	if ! addFiles "$_hostPath" \
	              "$_logFile"; then

		return 1
	else
		echo "OK"
	fi

	return
}

########################################################################
# MAIN
########################################################################

if [ "EMPTY${1}" = "EMPTY" ]; then

	usageMsg
	exit $_EXIT_USAGE
fi

_nfsrb_configFile="$1"

if [ -e "$PWD/$_nfsrb_configFile" ]; then

	_nfsrb_configFile="./$_nfsrb_configFile"
fi

if [ ! -e "$_NFSRB_CONFIG_DIR" ]; then

	mkdir -m og-rwx "$_NFSRB_CONFIG_DIR"
fi

########################################################################
# Variables in configuration file
########################################################################
# * $_OS
# * $_HOSTNAME
# * $_DOMAIN
# * $_IP_ADDRESS
# * $_SWAP_FILE_SIZE
# * $_DNS_SERVER_ADDRESS
# * $_GATEWAY_ADDRESS
# * $_NFS_SERVER_ADDRESS
# * $_DOWNLOAD_MIRROR
# * $_OS_VERSION
# * $_PLATFORM
# * $_BASE_PATH_PREFIX
# * $_ADDITIONAL_SETS_TO_DOWNLOAD
# * $_KERNEL_TO_USE
# * $_ADDITIONAL_FILES_TO_DOWNLOAD
########################################################################
# Parse config
while IFS="=" read -r _var _value; do

	# ignore comments
	if [ $( expr index "${_var}" \# ) = "1" -o \
             "EMPTY${_var}" = "EMPTY" ]; then

		continue

	# remove quotes from values
	elif [ $( expr index "${_value}" \" ) = "1" ]; then

		_value="${_value%\"}"
		_value="${_value#\"}"
	fi

	#echo "export \"_${_var}=${_value}\""
	# "_var" => "__var"!
	export "_${_var}=${_value}"

done < "$_nfsrb_configFile"

#. "$_nfsrb_configFile"

# Now check environment for options and overwrite options from config file
# with them
_nfsrbVariables="_OS \
                 _HOSTNAME \
                 _DOMAIN \
                 _IP_ADDRESS \
                 _SWAP_FILE_SIZE \
                 _DNS_SERVER_ADDRESS \
                 _GATEWAY_ADDRESS \
                 _NFS_SERVER_ADDRESS \
                 _DOWNLOAD_MIRROR \
                 _OS_VERSION \
                 _PLATFORM \
                 _BASE_PATH_PREFIX \
                 _ADDITIONAL_SETS_TO_DOWNLOAD \
                 _KERNEL_TO_USE \
                 _ADDITIONAL_FILES_TO_DOWNLOAD"

for _var in $_nfsrbVariables; do

	eval "_value=\${$_var}"

	#echo "$_var $_value"

	if [ ! -z "$_value" ]; then

		#echo "export \"_${_var}=${_value}\""
		export "_${_var}=${_value}"
	fi
done

# configuration processing
#
# * check all vars for content
# * tolerate no content (=default) for the following var(s):
#   * _IP_ADDRESS => IP address is resolved from hostname and domain
#   * _ADDITIONAL_SETS_TO_DOWNLOAD => only base and etc sets are used
#   * this doesn't work for the kernel, as for example the sgi platform
#     has no default kernel that would work on all machines
#   * _ADDITIONAL_FILES_TO_DOWNLOAD => no additional files are
#     downloaded
#   * _BASE_PATH_PREFIX => if not used, defaults to $_NFSRB_DEFAULT_BASE_PATH_PREFIX

_mandatoryVariables="_OS \
                     _HOSTNAME \
                     _DOMAIN \
                     _SWAP_FILE_SIZE \
                     _DNS_SERVER_ADDRESS \
                     _GATEWAY_ADDRESS \
                     _NFS_SERVER_ADDRESS \
                     _DOWNLOAD_MIRROR \
                     _OS_VERSION \
                     _PLATFORM \
                     _KERNEL_TO_USE"

_unconfiguredMandatoryVars=$_FALSE

for _var in $_mandatoryVariables; do

	eval "_value=\${_$_var}"

	#echo "$_var $_value"

	if [ -z "$_value" ]; then

		echo "$_PROGRAM: Mandatory variable \`$_var' is unconfigured."

		_unconfiguredMandatoryVars=$_TRUE
	fi
done

if [ $_unconfiguredMandatoryVars -eq $_TRUE ]; then

	echo "$_PROGRAM: Cannot continue. Exiting."
	exit 1
fi

if [ "EMPTY${__IP_ADDRESS}" = "EMPTY" ]; then

	# resolve hostname and domain to IP address
	__IP_ADDRESS=$( getent hosts "${__HOSTNAME}.${__DOMAIN}" | cut -d ' ' -f 1 )

	if [ "EMPTY${__IP_ADDRESS}" = "EMPTY" ]; then

		echo "$_PROGRAM: Cannot determine IP address of \"${__HOSTNAME}.${__DOMAIN}\"."
		echo "$_PROGRAM: Cannot continue. Exiting."
		exit 1
	fi
fi

# Defaults

if [ "EMPTY${__BASE_PATH_PREFIX}" = "EMPTY" ]; then

	__BASE_PATH_PREFIX="$_NFSRB_DEFAULT_BASE_PATH_PREFIX"

fi

if [ "EMPTY${__ADD_FILES_TREE}" = "EMPTY" ]; then

	__ADD_FILES_TREE="$_NFSRB_DEFAULT_ADD_FILES_TREE"

fi

_nfsrb_cmdlineHash=$( hashString "$0 $@" )

if [ "$__OS" = "openbsd" ]; then

	openbsd_makeFileSystem "$_openbsd_defaultSets" \
	                       "$_openbsd_defaultSetsSince57" \
	                       "$_openbsd_signifySupportSince" \
	                       "$_openbsd_hashFileSince" \
	                       "$_openbsd_signatureFileName" \
	                       "$_openbsd_buildinfoFileName" \
	                       "$_openbsd_hashFileName" \
	                       "$_nfsrb_cmdlineHash"

elif [ "$__OS" = "netbsd" ]; then

	netbsd_makeFileSystem "$_netbsd_defaultSets" \
	                      "$_netbsd_hashFileName" \
	                      "$_nfsrb_cmdlineHash"
else
	echo "$_PROGRAM: OS \`$__OS' unknown. Cannot continue. Exiting!" 1>&2
	exit $_EXIT_USAGE
fi

if [ $? -ne 0 ]; then

	echo "$_PROGRAM: Cannot continue. Exiting!" 1>&2
	exit 1
fi




if [ "$_anyProblems" = "yes" ]; then

	echo "$_PROGRAM: Keeping \`$_tmpDir' due to errors during building."
else
	rm -rf "$_tmpDir"
fi

exit

