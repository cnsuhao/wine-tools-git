USE winetestbot;

ALTER TABLE VMs
  ADD ChildPid INT(5) NULL
      AFTER Status;
