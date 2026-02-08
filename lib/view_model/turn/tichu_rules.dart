int requiredPassesForTrick(int activePlayerCount) {
  if (activePlayerCount <= 1) {
    return 0;
  }
  return activePlayerCount - 1;
}
