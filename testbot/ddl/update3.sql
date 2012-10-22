USE winetestbot;

ALTER TABLE VMs
  ADD VmxHost VARCHAR(64) NULL AFTER Status;
