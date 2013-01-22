USE winetestbot;

ALTER TABLE VMs
  ADD Details VARCHAR(512) NULL
      AFTER Description;
