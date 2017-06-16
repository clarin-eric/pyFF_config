#!/bin/sh -x

venv_path='venv/' #'/srv/Python/venvs/2014-11-20_SPF/'
pyff_config_directory_path="${venv_path:?}/etc/pyff_config/"

#cd "$(dirname $(readlink -f "${0}"))" &&

_curl() {
    'curl' --verbose --silent --fail --show-error --ipv4 --tlsv1 \
      --connect-timeout 5 --max-time 80 --retry 5 --retry-delay 0 \
      --retry-max-time 60 --location --time-cond "$1" --output "$1" "$2"
    return $?
}

# TODO: centralize SAML metadata storage
pyff_fetch_md() {
    output_dir_path="${pyff_config_directory_path:?}/output/"
    id_feds_target_dir_path="$(readlink -f -- "${output_dir_path:?}/id_feds/")"
    temp_dir_path="$(readlink -f -- "$(mktemp -d -t 'pyff_fetch_md.XXXXXX')")" &&
    rsync --remove-source-files -auv "${id_feds_target_dir_path:?}/" "${temp_dir_path}" &&

    printf '%s \n' "Exporting SAML metadata batch about SPF SPs from SVN into ${output_dir_path} ..." &&

    svn export --revision '7127' --force --depth files \
      'https://svn.clarin.eu/aai/clarin-sp-metadata.xml' \
        "${output_dir_path:?}/md_about_spf_sps.xml" ||
    error="CLARIN SPF SAML metadata export from svn.clarin.eu repository -> exit status: $?; $error" &&

    printf '%s \n' "Updating SAML metadata batches about IdPs from identity federations into '${temp_dir_path:?}' unless already up-to-date in '${id_feds_target_dir_path:?}' ..." &&

    _curl "${temp_dir_path}/aconet.xml" 'https://eduid.at/md/aconet-registered.xml' ||
    error="pyff_fetch_md: ACOnet -> exit status: $?; $error"
    _curl "${temp_dir_path}/surfconext.xml" 'https://engine.surfconext.nl/authentication/proxy/idps-metadata/key:20140505?sp-entity-id=https://sp.catalog.clarin.eu' ||
    error="pyff_fetch_md: SURFconext -> exit status: $?; $error"
    _curl "${temp_dir_path}/dfn-aai-basic.xml" 'https://www.aai.dfn.de/fileadmin/metadata/dfn-aai-basic-metadata.xml' ||
    error="pyff_fetch_md: DFN-AAI-Basic & Advanced -> exit status: $?; $error"
    _curl "${temp_dir_path}/haka.xml" 'https://haka.funet.fi/metadata/haka-metadata.xml' ||
    error="pyff_fetch_md: Haka -> exit status: $?; $error"
#    _curl "${temp_dir_path}/kalmar.xml" 'https://kalmar2.org/simplesaml/module.php/aggregator/?id=kalmarcentral2&amp;set=saml2' || error="pyff_fetch_md: Kalmar Union -> exit status: $?; $error"
    _curl "${temp_dir_path}/belnet.xml" 'https://federation.belnet.be/federation-metadata.xml' ||
    error="pyff_fetch_md: Belnet -> exit status: $?; $error"
    _curl "${temp_dir_path}/eduidcz.xml" 'https://metadata.eduid.cz/entities/eduid+idp' ||
    error="pyff_fetch_md: eduID.cz -> exit status: $?; $error"
    _curl "${temp_dir_path}/swamid_edugain.xml" 'https://md.swamid.se/md/swamid-edugain-1.0.xml' ||
    error="pyff_fetch_md: SWAMID eduGAIN -> exit status: $?; $error"
    _curl "${temp_dir_path}/arnesaai_edugain.xml" 'https://ds.aai.arnes.si/metadata/arnesaai2edugain.signed.xml' ||
    error="pyff_fetch_md: ArnesAAI eduGAIN -> exit status: $?; $error"
    _curl "${temp_dir_path}/edugain.xml" 'https://mds.edugain.org/' ||
    error="pyff_fetch_md: eduGAIN -> exit status: $?; $error"

    rsync --remove-source-files -auv "${temp_dir_path}/" "${id_feds_target_dir_path}"
    # && mv -v -b -S 'orig' -T  "${id_feds_target_dir_path}" || error="pyff_fetch_md: error during swapping '${temp_dir_path}' and '${id_feds_target_dir_path}' -> exit status: $?; $error"

    if [ -n "${error}" ]; then
        printf '%s \n' 'One or more errors occurred: ' "$error" ;
        unset error
        return 1
        # TODO: distinguish fatal and nonfatal failure
    fi
    printf '%s \n' "SAML metadata batches about IdPs up-to-date in '${id_feds_target_dir_path}'."
}

pyff_activate() {
   # shellcheck disable=SC1090
   . "${venv_path}/bin/activate" &&
   return $?
}

pyff_run() {
    #cd "${pyff_config_directory_path}" &&
    printf '%s\n' "Running PyFF job ${1}"
    pyff --loglevel=INFO "${1}".fd
    return $?
}

pyff_sign() {
    xmlsectool_parameters="--sign --digest SHA-512 --key /root/keys/SPF_signing_priv.pem --certificate /root/keys/SPF_signing_pub.crt --referenceIdAttributeName ID "
    old_JAVA_HOME="${JAVA_HOME}"
    JAVA_HOME='/usr/lib/jvm/java-7-openjdk-amd64/jre/'
    export JAVA_HOME
    # TODO: use $output_dir_path
    # shellcheck disable=SC2086
    'xmlsectool.sh' --inFile 'output/md_about_spf_sps.xml' --outFile \
      'output/md_about_spf_sps.xml' $xmlsectool_parameters ||
    error="pyff_sign: md_about_spf_sps -> exit status: $?; $error"
    # shellcheck disable=SC2086
    'xmlsectool.sh' --inFile 'output/prod_md_about_clarin_erics_idp.xml' --outFile \
      'output/prod_md_about_clarin_erics_idp.xml' $xmlsectool_parameters ||
    error="pyff_sign: prod_md_about_clarin_erics_idp -> exit status: $?; $error"
    # shellcheck disable=SC2086
    'xmlsectool.sh' --inFile 'output/prod_md_about_clarin_erics_idm.xml' --outFile \
      'output/prod_md_about_clarin_erics_idm.xml' $xmlsectool_parameters ||
    error="pyff_sign: prod_md_about_clarin_erics_idm -> exit status: $?; $error"
    # shellcheck disable=SC2086
    'xmlsectool.sh' --inFile 'output/beta_md_about_clarin_erics_idm.xml' --outFile \
      'output/beta_md_about_clarin_erics_idm.xml' $xmlsectool_parameters ||
    error="pyff_sign: beta_md_about_clarin_erics_idm -> exit status: $?; $error"
    # shellcheck disable=SC2086
    'xmlsectool.sh' --inFile 'output/prod_md_about_spf_idps.xml' --outFile \
      'output/prod_md_about_spf_idps.xml' $xmlsectool_parameters ||
    error="pyff_sign: prod_md_about_spf_idps -> exit status: $?; $error"
    # shellcheck disable=SC2086
    'xmlsectool.sh' --inFile 'output/prod_md_about_spf_sps.xml' --outFile \
      'output/prod_md_about_spf_sps.xml' $xmlsectool_parameters ||
    error="pyff_sign: prod_md_about_spf_sps -> exit status: $?; $error"
    JAVA_HOME="${old_JAVA_HOME}"
    export JAVA_HOME
    if [ -n "${error}" ]; then
        printf '%s \n' 'One or more errors occurred: ' "$error" ;
        unset error
        return 1
        # TODO: distinguish fatal and nonfatal failure
    fi
    printf '%s \n' 'Signed SAML metadata batches ... ' ;
}

pyff_verify_signatures() {
    xmlsectool_parameters=" --verifySignature --certificate /root/keys/SPF_signing_pub.crt "
    old_JAVA_HOME="${JAVA_HOME}"
    JAVA_HOME='/usr/lib/jvm/java-7-openjdk-amd64/jre/'
    export JAVA_HOME
    # shellcheck disable=SC2086
    'xmlsectool.sh' --inFile 'output/md_about_spf_sps.xml' $xmlsectool_parameters ||
    error="pyff_verify_signatures: md_about_spf_sps -> exit status: $?; $error"
    # shellcheck disable=SC2086
    'xmlsectool.sh' --inFile 'output/prod_md_about_clarin_erics_idp.xml' $xmlsectool_parameters ||
    error="pyff_verify_signatures: prod_md_about_clarin_erics_idp -> exit status: $?; $error"
    # shellcheck disable=SC2086
    'xmlsectool.sh' --inFile 'output/prod_md_about_clarin_erics_idm.xml' $xmlsectool_parameters ||
    error="pyff_verify_signatures: prod_md_about_clarin_erics_idm -> exit status: $?; $error"
    # shellcheck disable=SC2086
    'xmlsectool.sh' --inFile 'output/beta_md_about_clarin_erics_idm.xml' $xmlsectool_parameters ||
    error="pyff_verify_signatures: beta_md_about_clarin_erics_idm -> exit status: $?; $error"
    # shellcheck disable=SC2086
    'xmlsectool.sh' --inFile 'output/prod_md_about_spf_idps.xml' $xmlsectool_parameters ||
    error="pyff_verify_signatures: prod_md_about_spf_idps -> exit status: $?; $error"
    # shellcheck disable=SC2086
    'xmlsectool.sh' --inFile 'output/prod_md_about_spf_sps.xml' $xmlsectool_parameters ||
    error="pyff_verify_signatures: prod_md_about_spf_sps -> exit status: $?; $error"
    JAVA_HOME="${old_JAVA_HOME}"
    export JAVA_HOME
    if [ -n "${error}" ]; then
        printf '%s \n' 'One or more errors occurred:' "$error"
        unset error
        return 1
        # TODO: distinguish fatal and nonfatal failure
    fi
    printf '%s \n' 'Verified SAML metadata batch signatures ... '
}

pyff_publish() {
    old_JAVA_HOME="${JAVA_HOME}"
    JAVA_HOME='/usr/lib/jvm/java-7-openjdk-amd64/jre/'
    export JAVA_HOME
    chown -Rv '0:www-data' 'output/' &&
    chmod -Rv 'u=rw,g=r,o=' 'output/' &&
    mv 'output/md_about_spf_sps.xml' 'output/prod_md_about_clarin_erics_idp.xml' \
      'output/prod_md_about_clarin_erics_idm.xml' 'output/beta_md_about_clarin_erics_idm.xml' \
      'output/prod_md_about_spf_idps.xml' 'output/prod_md_about_spf_sps.xml' \
      -t '/srv/www/infra.clarin.eu/aai/' &&
    (cd '/srv/scripts/exec/SAML_metadata_QA_validator/' &&
    ant &&
    chown -v '0:www-data' 'out/md_about_spf_sps.svrlt' \
      'out/md_about_spf_sps_qa.xml' 'out/prod_md_about_spf_sps.svrlt' \
      'out/prod_md_about_spf_sps_qa.xml' &&
    chmod -v 'u=rw,g=r,o=' 'out/md_about_spf_sps.svrlt' \
      'out/md_about_spf_sps_qa.xml' 'out/prod_md_about_spf_sps.svrlt' \
      'out/prod_md_about_spf_sps_qa.xml' &&
    cp -a 'out/md_about_spf_sps.svrlt' 'out/md_about_spf_sps_qa.xml' \
      'out/prod_md_about_spf_sps.svrlt' 'out/prod_md_about_spf_sps_qa.xml' \
      -t '/srv/www/infra.clarin.eu/aai/') &&
    JAVA_HOME="${old_JAVA_HOME}"
    export JAVA_HOME &&
    return $?
}
