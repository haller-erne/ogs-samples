# ST04-kemulti-im24v

This OGS sample project shows how to exchange IO data with a IM24V module plugged
into a KE350 box. OGS uses the MID500/501 and MID0504 to exchange the custom
OpenProtocol IO signals.
As a multispindle controller can not control tools individually, this sample shows
how to multiplex two externally connected start switches (over IM24V inputs) in OGS
for setting the `FO1 CW` start signal of the controller. The currently selected
program (application number) is used to use the first or the second start switch.


(todo).