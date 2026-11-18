#!/usr/bin/env python3
"""Grab one frame from the capture card (/dev/video0, MJPG 640x480) after letting it settle; usage: cap.py out.png"""
import cv2,sys,time
c=cv2.VideoCapture(0,cv2.CAP_V4L2)
c.set(cv2.CAP_PROP_FOURCC,cv2.VideoWriter_fourcc(*'MJPG'))
print(c.isOpened(),c.get(3),c.get(4))
for i in range(15): ok,f=c.read(); time.sleep(0.1)
print(ok, None if f is None else f.shape, None if f is None else f.mean())
if ok: cv2.imwrite(sys.argv[1],f)
