# License and distribution checklist

The project retains upstream's GPL version 3-or-later grant and the unmodified root [LICENSE](../LICENSE). The [fork notice](../NOTICE.md) identifies modifications and their dates. Source-level copyrights remain in place; product-focused branding does not erase authorship.

This is a maintainer checklist derived from GPLv3 §§4–6, not legal advice or a claim that all distribution/regulatory questions have been resolved. Consult the [full license](../LICENSE) and [GNU FAQ](https://www.gnu.org/licenses/gpl-faq.html), and get qualified advice for the proposed distribution channel when needed.

## Before sharing a binary

- Identify the exact source revision used, including fork changes. Publish or otherwise provide the **complete corresponding source** using a GPL-permitted method. A link to an older upstream tree is not enough.
- Include build scripts, dependency revisions and installation information where required. Use your own signing setup; never expose private signing keys as an incidental repository cleanup.
- Keep the GPL text, warranty disclaimer, author notices and modified-version/date notices. Preserve Settings → About & licenses and its offline legal text.
- Ship required third-party notices with the binary, not just a web README. This fork bundles the four resolved Swift-package licenses and preserves upstream's Icons8 credit. Recheck notices after dependency changes, including any upstream `NOTICE` files.
- Audit vendored source and legacy assets for individual terms. [NOTICE.md](../NOTICE.md) is not an exhaustive rights clearance for every inherited image, sound or copied source file. GPL does not automatically license third-party trademarks or all bundled media.
- Do not add restrictions contradicting recipients' GPL rights. Review App Store/TestFlight terms, signing/install constraints and the intended distribution arrangement before a public release. This repository does not declare those questions solved.
- Review privacy and applicable medical-device/consumer-health obligations separately. GPL compliance does not establish safety, effectiveness, regulatory clearance or permission to make longevity claims.

## Verified by this cleanup

The root license and existing copyright headers are retained. The fork is identified prominently and dated. GPL and current resolved package notices are available offline in the iPhone target. Documentation separates experimental learning from health promises. The workspace lockfile records dependency provenance.

## Still a release gate

Asset-by-asset rights review, a complete vendored-code license audit, channel-specific legal review and a source bundle matching any publicly distributed binary must be completed for that release. Publishing this source does not constitute approval for a public binary release or TestFlight distribution.
