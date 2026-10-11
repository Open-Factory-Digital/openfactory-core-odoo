# The Odoo dev image: Odoo's own runtime (the official image — Python, its dependencies,
# wkhtmltopdf), running odoo-bin FROM YOUR FORK's checkout, mounted (or synced) at /opt/odoo/src.
# The odoo package the base image installs is shadowed: odoo-bin puts its own directory first
# on sys.path, so `import odoo` is the fork's.
ARG ODOO_VERSION=19.0
FROM odoo:${ODOO_VERSION}

USER root
COPY of-odoo-run /usr/local/bin/of-odoo-run
COPY of-odoo-test /usr/local/bin/of-odoo-test
RUN chmod 0755 /usr/local/bin/of-odoo-run /usr/local/bin/of-odoo-test \
 && mkdir -p /opt/odoo/src /opt/odoo/overlay && chown -R odoo /opt/odoo
USER odoo
ENV OF_ODOO_SRC=/opt/odoo/src
WORKDIR /opt/odoo
ENTRYPOINT ["/usr/local/bin/of-odoo-run"]
CMD []
