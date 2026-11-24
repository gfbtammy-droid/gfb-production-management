alter table public.loss_reports drop constraint if exists loss_reports_loss_type_check;
alter table public.loss_reports add constraint loss_reports_loss_type_check check (loss_type = any (array['WASTAGE','EXPIRED','AIR_LEAK_TEST','SPILLAGE','TORN_BAG','DAMAGED_PACK','MACHINE_FAULT','CONTAMINATION','RESIDUE','OTHER']));
