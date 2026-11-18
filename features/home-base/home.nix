# Identity of the home-manager user every host carries.
{ user, ... }:

{
  home.homeDirectory = "/home/${user}";
  # Release this home's state was created under; changing it is a migration.
  home.stateVersion = "25.11";
  home.username = user;
}
