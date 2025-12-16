package com.gamemetrics.userservice.service;

import com.gamemetrics.userservice.model.User;
import com.gamemetrics.userservice.repository.UserRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.UUID;

@Service
public class UserService {
    
    @Autowired
    private UserRepository userRepository;
    
    public User getUser(String id) {
        return userRepository.findById(id).orElse(null);
    }
    
    public User createUser(User user) {
        user.setId(UUID.randomUUID().toString());
        user.setCreatedAt(LocalDateTime.now());
        user.setUpdatedAt(LocalDateTime.now());
        return userRepository.save(user);
    }
    
    public User updateUser(String id, User user) {
        User existing = userRepository.findById(id).orElseThrow();
        existing.setEmail(user.getEmail());
        existing.setUsername(user.getUsername());
        existing.setFirstName(user.getFirstName());
        existing.setLastName(user.getLastName());
        existing.setUpdatedAt(LocalDateTime.now());
        return userRepository.save(existing);
    }
    
    public void deleteUser(String id) {
        // GDPR compliance: Hard delete all user data
        userRepository.deleteById(id);
        // In production, also delete from related tables
    }
}



