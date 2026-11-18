# HDMI check with a USB capture card (MacroSilicon MS2109 "USB Video")
Plug the card into the board's USB port, put the port in host mode (`sudo zynqmini-usb-role host` on the PYNQ image),
then on the board (PYNQ venv has OpenCV): `sudo python3 cap.py out.png`. Compare with `classify.py out.png`.
The card shows colour bars when it has no signal, `card_nosignal_placeholder.png`: a capture that equals it means NO picture.
`vivado_bars_reference.png` and `openflow_bars.png` are real 640x480 captures of the same bars (pixel-identical).
