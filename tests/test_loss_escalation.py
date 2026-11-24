import os
from playwright.sync_api import sync_playwright
HERE=os.path.dirname(os.path.abspath(__file__));REPO=os.path.dirname(HERE);O='https://demo.local/p/'
FAKE=open(os.path.join(HERE,'fake-supabase.js')).read()
def h(route):
    u=route.request.url
    if 'supabase-js' in u: return route.fulfill(status=200,content_type='application/javascript',body=FAKE)
    if u.startswith(O):
        f=os.path.join(REPO,(u[len(O):].split('?')[0].split('#')[0] or 'index.html'))
        if os.path.isfile(f):return route.fulfill(status=200,content_type='text/html',body=open(f,'rb').read())
    return route.abort()
res=[];ok=lambda n,c,i='':res.append(('PASS' if c else 'FAIL',n,i))
os.makedirs(os.path.join(HERE,'out'),exist_ok=True)
with sync_playwright() as p:
    br=p.chromium.launch()
    for w,tag in [(1300,'desk'),(390,'mob')]:
        ctx=br.new_context(viewport={'width':w,'height':900},locale='en-GB',timezone_id='Asia/Kuala_Lumpur');ctx.route('**/*',h);pg=ctx.new_page();errs=[];pg.on('pageerror',lambda e:errs.append(str(e)))
        pg.add_init_script("localStorage.setItem('gfbp_lang','en');window.print=()=>{}")
        pg.goto(O);pg.wait_for_timeout(1500)
        # report a loss and escalate to Production Sup
        pg.evaluate("openLossForm(null,1)");pg.wait_for_timeout(400)
        ok(tag+' escalate list has users',pg.evaluate("[...document.querySelectorAll('#l_chk option')].map(o=>o.textContent).join('|')").count('Production Sup')==1)
        pg.fill('#l_qty','3');pg.fill('#l_desc','Valve leak');pg.select_option('#l_chk','u3');pg.wait_for_timeout(100)
        ok(tag+' no-email warning',"no email" in pg.inner_text('#l_chkw'))
        pg.select_option('#l_chk','u2');pg.click('#ls');pg.wait_for_timeout(700)
        r=pg.evaluate("__T.loss_reports.slice(-1)[0]");ok(tag+' check_to saved',r.get('check_to')=='u2',r.get('check_to'))
        pg.evaluate("__T.loss_reports.slice(-1)[0].check_to_name='Production Sup'");lid=r['id']
        pg.evaluate(f"S.losses.find(x=>x.id==={lid}).check_to_name='Production Sup';openLoss({lid})");pg.wait_for_timeout(400)
        t=pg.inner_text('.sheet');ok(tag+' steps show waiting checker','Prepared by' in t and 'Production Sup' in t and 'Waiting for' in t)
        pg.screenshot(path=os.path.join(HERE,'out',f'esc_open_{tag}.png'))
        # admin checks and escalates to Inventory
        pg.click('#signL');pg.wait_for_timeout(300);pg.select_option('#f_v','u3');pg.click('#fsb');pg.wait_for_timeout(500)
        r=pg.evaluate(f"__T.loss_reports.find(x=>x.id==={lid})");ok(tag+' checked + verify_to',r.get('status')=='CHECKED' and r.get('verify_to')=='u3',(r.get('status'),r.get('verify_to')))
        ok(tag+' verify buttons',pg.locator('#verL').count()==1 and pg.locator('#backL').count()==1)
        pg.click('#backL');pg.wait_for_timeout(300);pg.fill('#f_n','qty wrong');pg.click('#fsb');pg.wait_for_timeout(500)
        r=pg.evaluate(f"__T.loss_reports.find(x=>x.id==={lid})");ok(tag+' sent back',r.get('status')=='OPEN' and r.get('verify_note')=='qty wrong')
        pg.evaluate(f"Object.assign(__T.loss_reports.find(x=>x.id==={lid}),{{status:'CHECKED'}});Object.assign(S.losses.find(x=>x.id==={lid}),{{status:'CHECKED'}});openLoss({lid})");pg.wait_for_timeout(300)
        pg.click('#verL');pg.wait_for_timeout(500)
        ok(tag+' verified closed',pg.evaluate(f"__T.loss_reports.find(x=>x.id==={lid}).status")=='CLOSED')
        # For me chip (admin u1 assigned as checker on another report)
        pg.evaluate("__T.loss_reports[0].check_to='u1';S.losses.find(x=>x.id===51).check_to='u1';closeSheet();S.tab='loss';S.lossF='MINE';render()");pg.wait_for_timeout(300)
        ok(tag+' For me filter',pg.evaluate("document.querySelectorAll('[data-lid]').length")==1)
        # deep link
        pg2=ctx.new_page();pg2.add_init_script("localStorage.setItem('gfbp_lang','en')");pg2.goto(O+'#loss-51');pg2.wait_for_timeout(1500);ok(tag+' email link opens report','LOSS-0051' in pg2.inner_text('.sheet') if pg2.locator('.sheet').count() else False);pg2.close()
        if tag=='desk':
            pg.evaluate("closeSheet();S.tab='more';render()");pg.wait_for_timeout(800)
            ok('settings email panel','Email reminders' in pg.inner_text('#app') and pg.locator('#ntT').count()==1)
            pg.screenshot(path=os.path.join(HERE,'out','esc_settings.png'),full_page=True)
            pg.evaluate("editUser(S.users?S.users[1]:S.people[1])");pg.wait_for_timeout(300);ok('user email field',pg.locator('#f_e').count()==1)
        ok(tag+' no errors',not errs,errs)
        ctx.close()
    br.close()
for r in res:print(*r)
