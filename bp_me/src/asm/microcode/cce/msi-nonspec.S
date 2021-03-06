# This microcode uses MSI protocol

#include "microcode.h"

# send sync messages
# r0 counts up from 0 number of sync messages sent
# r1 holds constant numLCE
# r3 stores the constant SYNC_ACK to check response ack type against
# The CCE waits for sync ack after each sync command. This avoids additional buffering being
# required in the CCE, at a small "performance" cost during startup
sync_init: movi 0 r0
movpg numLCE r1
movi SYNC_ACK r3
sync_top: bge r0 r1 finish_init
pushq lceCmd SYNC addr=0 lce=r0 way=0
popq lceResp r4
inc r0
bi sync_top

# set default value for mshr.next_coh_state
finish_init: movip COH_S cohSt

# Ready Routine
ready: wfq lceReq

# LCE Request Routine
lce_req: clm
poph lceReq r0
bf uncached_req ucf
rdp addr=req
bf ready pf
popq lceReq wp
rdw addr=req lce=req lru_way=lru
gad
# fall through

# Replacement Check Routine
replace_check: bfz next_coh_state rf

# Replacement Routine
replace: pushq lceCmd WB addr=lru lce=req way=lru
# wait for writeback response
replacement_poph: poph lceResp r0
beqi r0 COH_ACK replacement_poph
bf complete_replacement nwbf
pushq memCmd MEM_CMD_WR addr=lru lce=req way=lru wp=1
complete_replacement: popq lceResp

# Next Coherence State Routine
# write request means set to M, else read means set to S
next_coh_state: bf next_coh_set_m rqf
next_coh_set_s: movis COH_S nextCohSt
bi inv_check
next_coh_set_m: movis COH_M nextCohSt
# fall through to inv_check

# Invalidation Check
inv_check: bfnot upgrade_check rqf csf pt

# Invalidation Routine
invalidate: inv

# Upgrade Check Routine
upgrade_check: bfz set_entry uf pt

# Upgrade Routine
upgrade: wds addr=req lce=req way=req state=nextCohSt
pushq lceCmd STW addr=req lce=req way=req
bi ready

set_entry: wde addr=req lce=req way=lru state=nextCohSt

# Transfer Check
transfer_check: bfz read_l2 cmf pt

# Transfer routine - other cache has block in M
# write requests invalidate owner, read requests downgrade owner to S and writeback
transfer: bf transfer_write rqf

# transfer from owner in M, downgrade owner to S, send block to req in S
movis COH_S nextCohSt
pushq lceCmd ST addr=req lce=owner way=owner
wds addr=req lce=owner way=owner state=nextCohSt
pushq lceCmd TR addr=req lce=owner way=owner
pushq lceCmd WB addr=req lce=owner way=owner
# wait for transfer WB response
transfer_poph: poph lceResp r0
beqi r0 COH_ACK transfer_poph
bf complete_transfer nwbf
pushq memCmd MEM_CMD_WR addr=req lce=owner way=owner wp=1
complete_transfer: popq lceResp
bi ready

transfer_write: movis COH_I nextCohSt
pushq lceCmd ST addr=req lce=owner way=owner
wds addr=req lce=owner way=owner state=nextCohSt
movis COH_M nextCohSt
pushq lceCmd TR addr=req lce=owner way=owner
bi ready

# Read Line from L2 Routine
read_l2: pushq memCmd MEM_CMD_RD addr=req lce=req way=lru wp=1
bi ready

# Uncached Request Routine
uncached_req: bf uncached_store rqf
pushq memCmd MEM_CMD_UC_RD addr=req lce=req
popq lceReq
bi ready
uncached_store: pushq memCmd MEM_CMD_UC_WR addr=req lce=req
popq lceReq
bi ready

