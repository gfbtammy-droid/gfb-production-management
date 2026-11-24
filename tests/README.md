# Production app test kit (made-up jobs only)

`test_jobs.py` opens the real `index.html` in a headless browser with `fake-supabase.js` in place of Supabase (8 sample jobs in different states, no real data), on desktop and phone sizes. `test_loss_print.py` checks printing / PDF of one loss report and of the loss list. `test_jobs.py` checks the Waiting to pack and QC pending filters, the dashboard lists, the job page with several packing JOBs, and saving a loss report with a CMMS reference.

```
pip install playwright && playwright install chromium
python3 tests/test_jobs.py
```

Add sample jobs in `fake-supabase.js` (`T.job_orders`) when a new feature needs them. Screenshots go to `tests/out/` (ignored by git).
