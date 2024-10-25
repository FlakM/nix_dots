{ config, pkgs, pkgsUnstable, libs, ... }:
{

  home.packages = with pkgs; [
    jira-cli-go
  ];

  home.file.".jira/.config.yml" = {
    text = ''
      board:
          id: 1740
          name: Core Rust
          type: scrum
      epic:
          name: customfield_10005
          link: ""
      installation: Cloud
      issue:
          fields:
              custom:
                  - name: sprint
                    key: customfield_10010
                    schema:
                      datatype: number
                  - name: story-points
                    key: customfield_12191
                    schema:
                      datatype: number
          types:
              - id: "10003"
                name: Story
                handle: Story
                subtask: false
              - id: "10001"
                name: Zadanie
                handle: Task
                subtask: false
              - id: "10004"
                name: Błąd w programie
                handle: Bug
                subtask: false
              - id: "10002"
                name: Podzadanie
                handle: Sub-task
                subtask: true
              - id: "11930"
                name: Sub-bug
                handle: Sub-bug
                subtask: true
              - id: "10000"
                name: Epik
                handle: Epic
                subtask: false
      login: maciej.flak@modivo.com
      project:
          key: CORE
          type: classic
      server: https://modivo.atlassian.net'';
  };


}
