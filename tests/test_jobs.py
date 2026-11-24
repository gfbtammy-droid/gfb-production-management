import os
from playwright.sync_api import sync_playwright
HERE=os.path.dirname(os.path.abspath(__file__));REPO=os.path.dirname(HERE);O='https://demo.local/p/'
FAKE=open(os.path.join(HERE,'fake-supabase.js')).read()
def h(route):
    u=route.request.url
    if 'supabase-js' in u: return route.fulfill(status=200,content_type='application/javascript',body=FAKE)
    if u.startswith(O):
        f=os.path.join(REPO,(u[len(O):].split('?')[0] or 'index.html'))
        if os.path.isfile(f):return route.fulfill(status=200,content_type='text/html',body=open(f,'rb').read())
    return route.abort()
res=[]
def ok(n,c,i=''):res.append(('PASS' if c else 'FAIL',n,i))
with sync_playwright() as p:
    br=p.chromium.launch()
    for w,tag in [(1300,'desk'),(390,'mob')]:
        ctx=br.new_context(viewport={'width':w,'height':900},locale='en-GB',timezone_id='Asia/Kuala_Lumpur');ctx.route('**/*',h);pg=ctx.new_page();errs=[];pg.on('pageerror',lambda e:errs.append(str(e)))
        pg.add_init_script("localStorage.setItem('gfbp_lang','en')")
        pg.goto(O);pg.wait_for_timeout(1500)
        chips=pg.evaluate("[...document.querySelectorAll('.chip')].map(c=>c.textContent.trim())")
        ok(tag+' chips',any(c.startswith('Waiting to pack2') for c in chips) and any(c.startswith('QC pending2') for c in chips),chips[:4])
        pg.click('.chip[data-f=WAITPACK]');pg.wait_for_timeout(300)
        n=pg.evaluate("document.querySelectorAll('tr[data-id],.job').length");ok(tag+' waitpack filter 2',n==2,n)
        pg.screenshot(path=os.path.join(HERE,'out')+f'/p_jobs_{tag}.png',full_page=True)
        pg.click('.chip[data-f=QCPEND]');pg.wait_for_timeout(300)
        n=pg.evaluate("[...document.querySelectorAll('tr[data-id],.job')].map(e=>e.dataset.id).join(',')");ok(tag+' qc filter',n in('4,3','3,4'),n)
        pg.evaluate("S.tab='dash';S.dashMode='month';render()");pg.wait_for_timeout(500)
        txt=pg.inner_text('#app');ok(tag+' dash lists','Waiting to pack' in txt and 'without QC result' in txt)
        pg.screenshot(path=os.path.join(HERE,'out')+f'/p_dash_{tag}.png',full_page=True)
        pg.evaluate("openJob(2)");pg.wait_for_timeout(500);t2=pg.inner_text('.sheet');ok(tag+' detail',('Packing' in t2 and '(3)' in t2 and 'Waiting to pack' in t2),'')
        pg.screenshot(path=os.path.join(HERE,'out')+f'/p_detail_{tag}.png')
        if tag=='desk':
            pg.evaluate("openLossForm(null,1)");pg.wait_for_timeout(500)
            pg.fill('#l_qty','5');pg.fill('#l_desc','Film jam');pg.fill('#l_cmms','wo-2611-006');pg.select_option('#l_chk','u2');pg.click('#ls');pg.wait_for_timeout(800)
            ok('loss report CMMS ref',pg.evaluate("__T.loss_reports.filter(l=>l.cmms_ref).map(l=>l.cmms_ref).join()")=='WO-2611-006')
            ok('new loss default unit KG',pg.evaluate("__T.loss_reports.slice(-1)[0].uom")=='KG')
            pg.evaluate("openLossForm(null,1)");pg.wait_for_timeout(400);pg.fill('#l_qty','40');pg.select_option('#l_uom','PCS');pg.fill('#l_desc','Torn pouches');pg.select_option('#l_chk','u2');pg.click('#ls');pg.wait_for_timeout(800)
            ok('loss saved in PCS',pg.evaluate("__T.loss_reports.slice(-1)[0].uom")=='PCS')
            pg.evaluate("closeSheet&&closeSheet();S.tab='loss';S.lossF='MONTH';render()");pg.wait_for_timeout(500)
            txt=pg.inner_text('#app');ok('loss month total 8 KG + other units','8 KG' in txt.replace('\n',' ') or '8\nKG' in txt,txt[:0]);ok('other units listed','2 ROLL' in txt and '40 PCS' in txt)
            pg.screenshot(path=os.path.join(HERE,'out','loss_uom.png'),full_page=True)
        print(tag,'errors',errs);ctx.close()
for r in res:print(*r)
