# Automated job B: publish production SAML metadata about the SPF’s SPs.
- load:
   - output/sps-metadata/production/
- select: 
- sort order_by .//md:Organization/md:OrganizationName[@xml:lang = "en"]
- pubinfo:
   publisher: https://clarin.eu/
- xslt:
    stylesheet: tidy.xsl
- finalize:
    name: "http://www.clarin.eu/spf"
    cacheDuration: PT5H
    validUntil: P10D
    ID: CLARIN_SPF_SPS_PROD
- publish: output/prod_md_about_spf_sps.xml
- stats
- certreport