\# PFAS Enterprise 5.0 — Release Rollback SOP



Document ID: SOP\_ROLLBACK

Version: 1.0

Status: Controlled



\## Purpose



Define the rollback procedure for governed software releases when validation, reproducibility, or deployment issues are identified after publication.



\## Scope



Applies to:



\* governed releases

\* validation releases

\* reproducibility releases

\* internal controlled deployments



\## Trigger Conditions



Rollback may be initiated if:



\* validation artifact inconsistency

\* failed reproducibility check

\* incorrect threshold values

\* missing provenance records

\* broken API deployment

\* evidence packet corruption

\* release tagging error



\## Roles



Release Owner:

Approve rollback decision.



Reviewer:

Verify evidence.



Operator:

Execute rollback.



\## Rollback Procedure



\### Step 1 — Freeze Investigation



Record:



\* release tag

\* commit hash

\* timestamp

\* observed issue



\### Step 2 — Disable Release



Mark release:



ROLLBACK PENDING



\### Step 3 — Restore Previous Stable Version



Example:



git checkout governed-v1.0.0



or



git revert <commit>



\### Step 4 — Validate Restoration



Confirm:



\* tests pass

\* evidence intact

\* API operational

\* provenance restored



\### Step 5 — Publish Rollback Record



Create:



validation/releases/<release>/rollback\_report.md



\## Exit Criteria



Rollback complete only if:



\* validation PASS

\* reviewer approval

\* release archived



\## Notes



This SOP supports governed internal software releases and is not regulatory approval or certification.



